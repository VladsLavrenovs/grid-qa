*** Settings ***
Documentation       Day 3 Network-layer checks under Grid using own
...                 Python keyword library (DNS, TLS, TCP ports).
Library             ../libraries/NetworkLibrary.py
Resource            ../resources/common.resource

*** Variables ***
${HOSTNAME}        grid.connectedovals.com
${MIN_CERT_DAYS}   14

*** Test Cases ***
Grid Hostname Resolves
    [Documentation]    DNS: the hostname must resolve via the OS resolver.
    [Tags]             network    dns    smoke
    ${ip}=             Dns Should Resolve    ${HOSTNAME}
    Log                Resolved to ${ip}

TLS Certificate Is Healthy
    [Documentation]    Cert must verify (trusted chain, matching hostname)
    ...                and have at leasy ${MIN_CERT_DAYS} days of validity.
    [Tags]             network    tls    smoke
    ${days}=           TLS Certificate Should Be Valid For Days    ${HOSTNAME}    ${MIN_CERT_DAYS}
    Log                ${days} days of certificate validity remaining

HTTPS Port Is Open
    [Documentation]    443 must accept TCP connections
    [Tags]             network    ports    smoke
    Port Should Be Open    ${HOSTNAME}    443

Plain HTTP Port Behaviour
    [Documentation]    Port 80 open is EXPECTED here (Cloudflare answers and 
    ...                redirects to HTTPS) - documents edge behaviour.
    [Tags]             network    ports
    Port Should Be Open  ${HOSTNAME}    80
    
Random High Port Is Not Exposed
    [Documentation]    NEGATIVE: nothing should answer on arbitrary port.
    [Tags]             network    ports    negative
    Port Should Be Closed  ${HOSTNAME}    8443

