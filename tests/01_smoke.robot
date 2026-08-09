*** Settings ***
Documentation       Day 1 smoke suite - proving the toolchain works.
...                 Tests here use only Builtin and String libraries.
Library             String

*** Variables ***
${APP_NAME}         Grid
${APP_URL}          https://grid.connectedovals.com
@{FEATURES}         habits      groups      stats       themes

*** Test Cases ***
Toolchain Works
    [Documentation]     If this passes, RF + Python + venv are wired correctly.
    [Tags]              smoke
    Should Be Equal     ${APP_NAME}     Grid
    Log                 Robot Framework is alive and testing ${APP_NAME}

App URL Is Well Formed
    [Documentation]     String checks on variable - no network.
    [Tags]              smoke
    Should Start With   ${APP_URL}      https://
    Should Contain      ${APP_URL}      connectedovals.com
    ${domain}=          Fetch From Right        ${APP_URL}      //
    Log                 Domain part: ${domain}

Feature List Sanity
    [Documentation]     Working with lists + a user keyword (see Keywords section).
    [Tags]              smoke       demo
    Length Should Be    ${FEATURES}     4
    List Should Contain Feature         habits
    List Should Contain Feature         stats

*** Keywords ***
List Should Contain Feature
    [Documentation]     My first user keyword - wraps a Builtin check.
    [Arguments]         ${feature}
    Should Contain      ${FEATURES}     ${feature}
    