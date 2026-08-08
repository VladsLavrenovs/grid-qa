*** Settings ***
Documentation       Shared variables and keywords for all grid-qa suites.

*** Variables ***
${BASE_URL}         https://grid.connectedovals.com

*** Keywords ***
Log Test Context
    [Documentation]     Example shared keyword: standard logging header.
    Log                 Target: ${BASE_URL}
    Log                 Suite: ${SUITE NAME} | Test: ${TEST NAME}