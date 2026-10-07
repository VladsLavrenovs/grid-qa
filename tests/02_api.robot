*** Settings ***
Documentation       Day 2 API tests against the live Grid project (Supabase backend).
...                 Auth: dedicated email/password test user, created in Supabase.
Library             Collections
Library             RequestsLibrary
Resource            ../resources/common.resource
Suite Setup         Create Sessions

*** Variables ***
${SUPABASE_URL}      %{SUPABASE_URL}
${SUPABASE_KEY}      %{SUPABASE_KEY}
${QA_USER_EMAIL}     %{QA_USER_EMAIL}
${QA_USER_PASS}      %{QA_USER_PASS}
# Non-secret fixture row owned by a second test user (user B)
${OTHER_USER_ROW_ID}    23afec65-33a2-48a9-8945-23529ef7a36c

*** Test Cases ***
Grid Website Is Reachable
    [Documentation]     Plain HTTPS GET on the public site - the front door works
    [Tags]              smoke    web
    ${response}=        GET On Session        web    /
    Status Should Be    200    ${response}

Auth Service Is Healthy
    [Documentation]     Supabase auth health endpoint responds.
    [Tags]              smoke    api
    ${response}=        GET On Session        api    /auth/v1/health
    Status Should Be    200    ${response}

Test User Can Log In
    [Documentation]     POST credentials, receive an access token. Token and user id are stored
    ...                 for the following tests (suite variable = Tosca buffer).
    ...                 Logging is muted around the credentials so log.html holds no secrets.
    [Tags]              api    auth
    [Teardown]          Set Log Level    ${old_level}
    ${old_level}=       Set Log Level         NONE
    ${body}=            Create Dictionary     email=${QA_USER_EMAIL}     password=${QA_USER_PASS}
    ${response}=        POST On Session       api    /auth/v1/token
    ...                 params=grant_type=password
    ...                 json=${body}
    ...                 expected_status=any
    Status Should Be    200    ${response}
    Set Suite Variable    ${ACCESS_TOKEN}    ${response.json()}[access_token]
    Set Log Level       ${old_level}
    Set Suite Variable    ${USER_ID}    ${response.json()}[user][id]
    Log                   Token acquired (length: ${{len($ACCESS_TOKEN)}} chars)

Authenticated User Can Read Only Own Data
    [Documentation]     Bearer token + anon key -> RLS returns ONLY this user's rows.
    ...                 Every returned row must belong to the logged-in user.
    ...                 Needs at least one habit for the test user, otherwise nothing is proven.
    [Tags]              api    auth
    ${headers}=         Create Dictionary   Authorization=Bearer ${ACCESS_TOKEN}
    ${response}=        GET On Session       api    /rest/v1/habits
    ...                 headers=${headers}
    ...                 params=select=*
    Status Should Be    200    ${response}
    ${rows}=            Set Variable    ${response.json()}
    Should Not Be Empty    ${rows}    Test user has no habits - RLS isolation cannot be verified
    FOR    ${row}    IN    @{rows}
        Should Be Equal    ${row}[user_id]    ${USER_ID}
    END
    Log                 Rows visible to test user: ${{len($rows)}} - all owned by ${USER_ID}

User Cannot Read Another User's Row
    [Documentation]     NEGATIVE test: user A asks for a row that belongs to user B, by its id.
    ...                 RLS filters rows instead of returning an error, so the expected
    ...                 result is 200 with an empty list [] - not 401/403.
    [Tags]              api    auth    negative    security
    ${headers}=         Create Dictionary   Authorization=Bearer ${ACCESS_TOKEN}
    ${response}=        GET On Session       api    /rest/v1/habits
    ...                 headers=${headers}
    ...                 params=id=eq.${OTHER_USER_ROW_ID}&select=*
    Status Should Be    200    ${response}
    Should Be Empty     ${response.json()}    User A can read user B's row - RLS leak!

Request Without API Key Is Rejected
    [Documentation]     NEGATIVE test: no apikey and no Bearer token -> the API gateway must refuse.
    ...                 expected_status stops RequestsLibrary failing early - we WANT the 401.
    [Tags]              api    negative
    ${response}=        GET On Session       bare    /rest/v1/habits
    ...                 expected_status=401
    ...                 params=select=*
    Log                 Correctly rejected with ${response.status_code}

Anon Key Without Token Sees No Rows
    [Documentation]     NEGATIVE test: apikey present, no Bearer token -> Postgres role 'anon'.
    ...                 Either refused (401) or RLS filters everything out (200 + empty list).
    [Tags]              api    negative
    ${response}=        GET On Session       api    /rest/v1/habits
    ...                 params=select=*
    ...                 expected_status=any
    Log                 anon -> ${response.status_code} ${response.text}
    IF    ${response.status_code} == 200
        Should Be Empty    ${response.json()}    Anonymous request returned rows - RLS leak!
    ELSE
        Should Be Equal As Integers    ${response.status_code}    401
    END


*** Keywords ***
Create Sessions
    [Documentation]     Three sessions: public website, API with anon key,
    ...                 and a 'bare' one with NO auth headers for negative tests.
    Create Session      web    ${BASE_URL}    verify=${True}
    &{api_headers}=    Create Dictionary    apikey=${SUPABASE_KEY}
    Create Session      api    ${SUPABASE_URL}    headers=${api_headers}      verify=${True}  
    Create Session      bare    ${SUPABASE_URL}    verify=${True}

