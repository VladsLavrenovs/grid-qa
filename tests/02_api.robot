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
    [Documentation]     POST credentials, recieve an access token. Token is stored
    ...                 for the following tests (suite variable = Tosca buffer).
    [Tags]              api    auth
    ${body}=           Create Dictionary     email=${QA_USER_EMAIL}     password=${QA_USER_PASS}
    ${response}=        POST On Session       api    /auth/v1/token   
    ...                 params=grant_type=password
    ...                 json=${body}
    Status Should Be    200    ${response}
    Dictionary Should Contain Key    ${response.json()}    access_token
    Set Suite Variable    ${ACCESS_TOKEN}    ${response.json()}[access_token]
    Log                   Token acquired (length: ${{len($ACCESS_TOKEN)}} chars)

Authenticate User Can Read Own Data
    [Documentation]     Bearer token + anon key -> RLS returns ONLY this user's rows.
    ...                 Adjust the table name to your schema if needed.
    [Tags]              api    auth
    ${headers}=         Create Dictionary   Authorization=Bearer ${ACCESS_TOKEN}
    ${response}=        GET On Session       api    /rest/v1/habits   
    ...                 headers=${headers}
    ...                 params=select=*
    Status Should Be    200    ${response}
    Log                 Rows visible to test user: ${{len(${response.json()})}}

Request Without Token Is Rejected
    [Documentation]     NEGATIVE test: no Bearer token -> the API must refuse.
    ...                 expected_status stpops RequestLibrary failing early - we WANT the 401.
    [Tags]              api    negative
    ${response}=        GET On Session       bare    /rest/v1/habits
    ...                 expected_status=401
    ...                 params=select=*
    Log                 Correctly rejected with ${response.status_code}



*** Keywords ***
Create Sessions
    [Documentation]     Three sessions: public website, API with anon key,
    ...                 and a 'bare' one with NO auth headers for negative tests.
    Create Session      web    ${BASE_URL}    verify=${True}
    &{api_headers}=    Create Dictionary    apikey=${SUPABASE_KEY}
    Create Session      api    ${SUPABASE_URL}    headers=${api_headers}      verify=${True}  
    Create Session      bare    ${SUPABASE_URL}    verify=${True}

