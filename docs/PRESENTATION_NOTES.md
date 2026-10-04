# grid-qa — Presentation Conspect

> Study notes for a 10–15 min presentation (network QA / DevOps role).
> Everything here was checked against the code in this repo. Values marked
> *(observed)* come from an actual run of the suites on 2026-10-04.

---

## 0. Elevator pitch (30 seconds, memorise this)

> "grid-qa is an automated test suite for **Grid**, a habit-tracker app I run in
> production at grid.connectedovals.com. It's written in **Robot Framework**
> with a **custom Python keyword library** for network checks. It tests three
> layers: **network** (DNS, TLS certificate health, open/closed ports),
> **API & auth** (login, row-level security, rejecting unauthenticated
> requests) and a **toolchain smoke** layer. A **GitLab CI** pipeline lints the
> code, runs the suite against the live system every night, and publishes a
> sanitised report to **Cloudflare Pages** at grid-qa.connectedovals.com. A
> failing night is visible on purpose."

Key numbers: **13 tests in 3 suites**, **1 custom Python library (4 keywords)**,
**3-stage pipeline**, built in **~5 days (6–11 Aug 2026)**, about **400 lines**
of real code and config.

---

## 1. The technical stack — what, and why

| Layer | Tool | What it does here | Why you chose it (talking point) |
|---|---|---|---|
| Test framework | **Robot Framework 7.4.2** | Runs the `.robot` test suites, generates `output.xml`, `report.html`, `log.html` | Keyword-driven and readable by non-developers. **It started at Nokia Networks**, so it's widely used in telecom and network testing. Similar idea to Tosca (your test code even says "suite variable = Tosca buffer"). |
| Language | **Python 3.12** | Custom keyword library, report generator script | RF is written in Python, so any Python class turns into keywords. The network checks use the standard library only. |
| HTTP testing | **RequestsLibrary 0.9.7** (wraps `requests 2.34`) | HTTP sessions, GET/POST, status assertions | The standard RF library for REST APIs. |
| Network checks | Python stdlib: `socket`, `ssl`, `datetime` | DNS resolution, TLS handshake and certificate reading, TCP connect | No extra dependencies, so the code stays transparent. You can explain every line. |
| Lint / format | **ruff 0.16.2** | `ruff check` (lint) + `ruff format --check` (formatting) | A fast single tool that replaces flake8, isort and black. Used as a quality gate. |
| CI/CD | **GitLab CI** (`.gitlab-ci.yml`) | lint → test → publish, nightly schedule | Common in enterprise and telecom companies, including Swisscom. Stages, artifacts and JUnit reports are built in. |
| Containers | Docker images `python:3.12-slim`, `node:20-slim` | Each job runs in a clean, throw-away container | Gives reproducible runs with no state on the runner. |
| Hosting of report | **Cloudflare Pages** via `wrangler` CLI | Serves `public/` at grid-qa.connectedovals.com | Free static hosting on a CDN. The domain is already on Cloudflare. |
| System under test | **Grid**, with a **Supabase** backend (Postgres + PostgREST + GoTrue auth), behind **Cloudflare** | The real production app | You test a real production app, not a demo app. |
| Source control | GitHub (this repo) + GitLab (pipeline) | — | The README badge points at the GitLab pipeline. |

**Supabase in one sentence:** a hosted Postgres database that gets an
automatic REST API (**PostgREST**, at `/rest/v1/...`) and an auth server
(**GoTrue**, at `/auth/v1/...`). Both sit behind a gateway (Kong) that
requires an `apikey` header. Data access is controlled by Postgres
**Row-Level Security (RLS)** policies, for example `user_id = auth.uid()`.

---

## 2. Architecture / data flow

```
 push to main  or  nightly schedule (GitLab → Build → Pipeline schedules)
        │
        ▼
 ┌────────┐     ┌──────────────────────────┐   artifacts    ┌──────────────┐
 │  lint  │ ──▶ │       robot-tests        │ ─────────────▶ │   publish    │
 └────────┘     └──────────────────────────┘ results/ +     └──────────────┘
 ruff check      robot → results/output.xml   public/        wrangler pages
 ruff format     (+ log.html, report.html,                   deploy public/
 robot --dryrun    xunit.xml → GitLab "Tests" tab)                 │
                 rebot --log NONE → public/report.html             ▼
                 make_index.py   → public/index.html      Cloudflare Pages
                 exit $RESULT  (job goes red if tests failed) grid-qa.connectedovals.com

        Tests hit:  grid.connectedovals.com (Cloudflare edge)  ← DNS/TLS/ports/HTTPS
                    <project>.supabase.co  (/auth/v1, /rest/v1) ← API/auth tests
```

`log.html` holds request-level detail such as URLs, headers and timings. It
stays in **private GitLab artifacts** (kept for 30 days) and is never
published.

---

## 3. Repository walkthrough (file by file)

```
grid-qa/
├── .gitlab-ci.yml            3-stage pipeline
├── requirements.txt          pinned deps (NB: saved as UTF-16, see §8)
├── README.md                 overview + design decisions
├── assets/Readme-diagram.png pipeline diagram
├── resources/common.resource shared variables/keywords (${BASE_URL})
├── tests/
│   ├── 01_smoke.robot        3 tests – toolchain sanity, no network
│   ├── 02_api.robot          5 tests – website + Supabase auth/RLS
│   └── 03_network.robot      5 tests – DNS, TLS, ports
├── libraries/NetworkLibrary.py   custom keywords (DNS/TLS/ports)
├── scripts/make_index.py     builds the summary landing page
├── site/index.html           HTML template with {{PLACEHOLDERS}}
└── public/index.html         generated output (committed copy is stale)
```

### `resources/common.resource`
* Defines `${BASE_URL} = https://grid.connectedovals.com`, which both live suites share.
* Defines the keyword `Log Test Context`. It is an example and no test uses it.
* Suites load it with `Resource ../resources/common.resource`.

### `libraries/NetworkLibrary.py`
A plain Python class. **Robot Framework turns every public method into a keyword:**
`dns_should_resolve` becomes `Dns Should Resolve` (keyword names ignore
case, spaces and underscores).
* **Pass or fail:** if a method raises `AssertionError`, the test fails with that message. If it returns normally, the test passes.
* **Return values** can be stored in RF: `${ip}=  Dns Should Resolve  host`.
* **Logging:** `print("*INFO* ...")` writes to the RF log at INFO level.
* **Arguments from RF arrive as strings**, so the code calls `int(port)`, `float(timeout)` and `int(min_days)`.

| Keyword | Mechanism | Fails when |
|---|---|---|
| `Dns Should Resolve host` | `socket.getaddrinfo(host, None)`, the OS resolver (same as a browser) | `socket.gaierror` (NXDOMAIN, no DNS) |
| `Tls Certificate Should Be Valid For Days host min_days=14 port=443` | TCP connect → `ssl.create_default_context()` → `wrap_socket(server_hostname=host)` (sends **SNI**, verifies **chain + hostname**) → `getpeercert()["notAfter"]` → days left | cert not trusted / hostname mismatch / expired / unreachable / fewer than `min_days` days left |
| `Port Should Be Open host port timeout=5` | `socket.create_connection` (TCP 3-way handshake) | refused / timeout / any OSError |
| `Port Should Be Closed host port timeout=3` | same, inverted | the connection **succeeds** |

### `scripts/make_index.py`
1. Loads `results/output.xml` with Robot's API: `robot.api.ExecutionResult`.
2. Reads `result.statistics.total` to get passed, failed and skipped counts.
3. Replaces `{{PASSED}}`, `{{TOTAL}}`, `{{STATUS_CLASS}}` (`pass`/`fail` sets a green or red CSS class) and `{{TIMESTAMP}}` (UTC) in `site/index.html`.
4. Writes the result to `public/index.html`. This is the landing page at grid-qa.connectedovals.com, which links to `report.html`.

### `site/index.html`
A static dark-theme page template with no JavaScript. It links to GitHub and to the GitLab pipelines.

---

## 4. Robot Framework crash course (be ready to explain the syntax)

```robot
*** Settings ***        # imports: Library, Resource, Suite Setup, Documentation
*** Variables ***       # suite-level variables
*** Test Cases ***      # each unindented line = a test name; indented lines = steps
*** Keywords ***        # user-defined keywords (functions)
```

| Syntax | Meaning | Where it's used |
|---|---|---|
| `${x}` | scalar variable | everywhere |
| `@{FEATURES}` | list variable | 01_smoke |
| `&{api_headers}` | dictionary variable | 02_api `Create Sessions` |
| `%{SUPABASE_URL}` | **environment variable** (this is how secrets come in) | 02_api |
| `${{ len($ACCESS_TOKEN) }}` | inline **Python expression** | 02_api log lines |
| `${var}=  Keyword  args` | store a keyword's return value | many |
| `...` | continue the previous line | multi-line args |
| two or more spaces | **separator between keyword and arguments** (this matters) | everywhere |
| `[Tags]` | labels; filter with `--include smoke` / `--exclude negative` | all tests |
| `[Documentation]`, `[Arguments]` | metadata / params of a user keyword | all |
| `Suite Setup` | runs once before the suite's tests | 02_api |
| `Set Suite Variable` | share a value between tests in the same suite | token in 02_api |

**Exit code:** `robot` returns the **number of failed tests** (0 means all
passed, capped at 250). The pipeline relies on this.

**Outputs:** `output.xml` (machine-readable), `log.html` (step-by-step detail),
`report.html` (summary). `--xunit` adds JUnit XML. **`rebot`** re-processes an
existing `output.xml` into new reports without re-running the tests.

**`--dryrun`:** parses every suite and checks that every keyword and library
exists, without executing anything. It works as a syntax and "link" check.

---

## 5. The CI/CD pipeline, line by line (`.gitlab-ci.yml`)

```yaml
stages: [lint, test, publish]        # run in this order; a failed stage stops later ones
```

**`lint`** (image `python:3.12-slim`)
* `pip install -r requirements.txt`. Each job starts in a fresh container, so it reinstalls.
* `ruff check libraries/` lints the code (unused imports, bad idioms…). The commit history shows a deliberate **negative test of the gate**: you added an unused `import os`, the pipeline went red, then you removed it and it went green (commits `ef7e70e` → `98762e3`). This is a good story to tell.
* `ruff format --check libraries/` checks formatting without changing files.
* `robot --dryrun tests/` checks that all suites parse and every keyword resolves.

**`robot-tests`** (stage `test`)
```bash
robot --outputdir results --xunit xunit.xml tests/ || RESULT=$?
```
* Runs **all 13 tests** against the live system.
* `|| RESULT=$?`: if tests fail, the exit code (the number of failures) is **saved instead of stopping the job**, so the report steps below still run.
```bash
rebot --outputdir public --log NONE --report report.html results/output.xml
```
* Rebuilds the report from `output.xml` **without log.html**. This is the "sanitised" public report.
```bash
python scripts/make_index.py      # builds public/index.html
exit ${RESULT:-0}                 # NOW fail the job if tests failed (default 0)
```
* This is the **"fail honestly, but always publish"** design.
* `artifacts: when: always` keeps `results/` and `public/` even if the job failed. `reports: junit:` makes GitLab show the tests in the pipeline's **Tests** tab. `expire_in: 30 days`.

**`publish`** (image `node:20-slim`, `when: always`)
* `when: always` makes publish run **even if robot-tests failed**, so a red night appears on the public page.
* Artifacts from earlier stages are downloaded automatically, so `public/` is available.
* `npx wrangler pages project create ... || true` is idempotent: it creates the project the first time and ignores the "already exists" error afterwards.
* `npx wrangler pages deploy public --project-name=grid-qa` uploads the folder to Cloudflare Pages.
* **Not in the YAML (configured in the GitLab UI):** masked CI/CD variables `SUPABASE_URL`, `SUPABASE_KEY`, `QA_USER_EMAIL`, `QA_USER_PASS`, plus `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (wrangler reads these), the **pipeline schedule** (cron, nightly), and the custom domain mapping in Cloudflare.

---

## 6. Every test in detail + how to replicate it manually at home

### 6.0 Preparation (do this the evening before)

```powershell
cd grid-qa
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
. .\set-env.ps1                 # sets $env:SUPABASE_URL, SUPABASE_KEY, QA_USER_EMAIL, QA_USER_PASS
robot --outputdir results tests/          # full run (13 tests)
start results\report.html                 # or log.html for step-by-step detail
```
Useful variants for the demo:
```powershell
robot --outputdir results --include smoke tests/                       # only smoke-tagged tests
robot --outputdir results -t "TLS Certificate Is Healthy" tests/03_network.robot  # one test
robot --outputdir results --loglevel DEBUG tests/02_api.robot          # full HTTP detail in log.html
robot --dryrun tests/                                                  # what the lint stage does
```

**Where the secret values come from:**
* `SUPABASE_URL` and `SUPABASE_KEY`: Supabase dashboard → *Project Settings → API* (Project URL + `anon`/publishable key). The anon key is **public by design**. It ships in the frontend JavaScript, and you can see it in browser DevTools → Network on Grid as the `apikey` header of requests to `*.supabase.co`. Security comes from **RLS**, not from hiding this key.
* `QA_USER_EMAIL` and `QA_USER_PASS` belong to the dedicated test user you created in Supabase → *Authentication → Users*. A separate user is needed because the real login is OAuth, which a script can't automate.
* In CI the same names exist as **masked GitLab CI/CD variables**.

> ⚠️ **On screen during the presentation:** never show `set-env.ps1`, the
> password, or a live access token. The token stays valid for about an hour.
> Showing the anon key is harmless, but it's cleaner not to.

---

### Suite 01 — `01_smoke.robot` (toolchain sanity, no network)

| Test | What it does | Under the hood |
|---|---|---|
| **Toolchain Works** | `Should Be Equal ${APP_NAME} Grid` + a log line | Proves RF, Python and the venv work. If even this fails, the environment is broken, not the app. |
| **App URL Is Well Formed** | `Should Start With https://`, `Should Contain connectedovals.com`, `Fetch From Right ${APP_URL} //` → `grid.connectedovals.com` | String keywords from the `String` library. Shows that config values are well formed. |
| **Feature List Sanity** | `Length Should Be @{FEATURES} 4`; user keyword `List Should Contain Feature` for `habits`, `stats` | Shows lists and a user-defined keyword with `[Arguments]`. |

Manual replication: `robot tests/01_smoke.robot`. The observed log values are
`Domain part: grid.connectedovals.com` and `Length is 4.`

Honest framing: *"Day-1 suite. It checks the toolchain and doesn't test the
product. In a real project this is the canary that tells you the test
environment itself is fine."*

---

### Suite 02 — `02_api.robot` (website + Supabase API/auth)

**Suite Setup `Create Sessions`** creates 3 HTTP sessions (persistent
`requests.Session` objects that keep base URL, headers and TLS verification):

| Session | Base URL | Headers | Purpose |
|---|---|---|---|
| `web` | `https://grid.connectedovals.com` | none | public website |
| `api` | `$SUPABASE_URL` | `apikey: <anon key>` | normal API calls |
| `bare` | `$SUPABASE_URL` | **none** | negative tests |

`verify=${True}` means the TLS certificate is always verified.

#### 2.1 Grid Website Is Reachable `[smoke web]`
* **Does:** `GET https://grid.connectedovals.com/` → expects **200**.
* **Manual:**
  ```powershell
  curl.exe -sS -o NUL -w "%{http_code} %{time_total}s %{remote_ip}`n" https://grid.connectedovals.com/
  curl.exe -sSI https://grid.connectedovals.com/      # headers: server: cloudflare, cf-ray, ...
  ```
  (In Windows PowerShell 5.1, `curl` is an alias for Invoke-WebRequest. Always type **`curl.exe`**.)
* **Explain:** `server: cloudflare` and the `cf-ray` header show that the request was answered by the Cloudflare edge, not by your origin server directly.

#### 2.2 Auth Service Is Healthy `[smoke api]`
* **Does:** `GET $SUPABASE_URL/auth/v1/health` with `apikey` → expects **200**.
* **Manual:**
  ```powershell
  curl.exe -s "$env:SUPABASE_URL/auth/v1/health" -H "apikey: $env:SUPABASE_KEY"
  ```
  Expected: JSON similar to `{"version":"v2.x.x","name":"GoTrue","description":"GoTrue is a user registration and authentication API"}`.
* **Explain:** GoTrue is Supabase's auth server. A health endpoint is the standard liveness probe, the same idea as a Kubernetes liveness check.

#### 2.3 Test User Can Log In `[api auth]`
* **Does:** `POST $SUPABASE_URL/auth/v1/token?grant_type=password` with JSON `{"email":..., "password":...}` → expects **200** and an `access_token` key in the body. It stores the token with **`Set Suite Variable ${ACCESS_TOKEN}`** for the next test and logs only its **length**, never the token itself.
* **Manual (PowerShell):**
  ```powershell
  $body  = @{ email = $env:QA_USER_EMAIL; password = $env:QA_USER_PASS } | ConvertTo-Json
  $login = Invoke-RestMethod -Method Post `
           -Uri "$env:SUPABASE_URL/auth/v1/token?grant_type=password" `
           -Headers @{ apikey = $env:SUPABASE_KEY } `
           -ContentType 'application/json' -Body $body
  $login | Select-Object token_type, expires_in       # bearer, 3600
  $login.access_token.Length                          # same number the test logs
  $login.user.id                                      # the user's UUID
  ```
* **What's in the response:** `access_token` (a **JWT**), `token_type: bearer`, `expires_in: 3600`, `refresh_token`, `user{...}`.
* **Decode the JWT locally.** Don't paste live tokens into jwt.io on a projector:
  ```powershell
  $p = $login.access_token.Split('.')[1].Replace('-','+').Replace('_','/')
  $p += '=' * ((4 - $p.Length % 4) % 4)
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
  ```
  You'll see `sub` (user id), `role: "authenticated"`, `email` and `exp` (expiry, unix time). A JWT has three parts, `header.payload.signature`. The payload is only base64-encoded, not encrypted. The signature is what prevents tampering.

#### 2.4 Authenticate User Can Read Own Data `[api auth]`
* **Does:** `GET $SUPABASE_URL/rest/v1/habits?select=*` with `apikey` (from the session) and `Authorization: Bearer <token>` → expects **200** and logs the row count.
* **What happens server-side:** PostgREST validates the JWT and runs the SQL as the Postgres role `authenticated`, with `auth.uid()` = `sub`. The **RLS policy** on `habits` then filters the rows, so only this user's rows come back.
* **Manual:**
  ```powershell
  $h = @{ apikey = $env:SUPABASE_KEY; Authorization = "Bearer $($login.access_token)" }
  $rows = Invoke-RestMethod -Uri "$env:SUPABASE_URL/rest/v1/habits?select=*" -Headers $h
  $rows.Count
  $rows | Select-Object -First 3 | Format-Table
  ```
* **Honest note:** the test checks status 200 and logs the count, but **it does not yet assert isolation** (that every row's `user_id` equals the token's `sub`). See §8. Know this before someone asks.

#### 2.5 Request Without Token Is Rejected `[api negative]`
* **Does:** uses the `bare` session, so it sends **neither `apikey` nor `Authorization`**. Sends `GET /rest/v1/habits?select=*` with `expected_status=401`. Without `expected_status`, RequestsLibrary would raise on any 4xx response. With it, the 401 is the expected result.
* **Manual:**
  ```powershell
  curl.exe -s -i "$env:SUPABASE_URL/rest/v1/habits?select=*"
  ```
  Expected: `HTTP/1.1 401` with a body like `{"message":"No API key found in request", "hint":"No 'apikey' request header or url param was found."}`.
* **Explain:** the API gateway rejects the request before it reaches the database.
* **Precise wording matters:** what this test proves is **"missing API key → 401"**. The README says "missing key vs missing token", but the "key present, token missing" case isn't a test yet. Try it manually. It's a nice live bonus:
  ```powershell
  curl.exe -s -i "$env:SUPABASE_URL/rest/v1/habits?select=*" -H "apikey: $env:SUPABASE_KEY"
  ```
  With RLS correctly configured you should get **200 with `[]`**: the anonymous role is allowed to ask but sees nothing. You might instead get 401/permission denied if the anon role has no grant on the table. **Check which one you get before the presentation.** Either way the data stays private, and that is the real RLS proof.

---

### Suite 03 — `03_network.robot` (custom NetworkLibrary)

Variables: `${HOSTNAME}=grid.connectedovals.com`, `${MIN_CERT_DAYS}=14`.

#### 3.1 Grid Hostname Resolves `[network dns smoke]`
* **Does:** `Dns Should Resolve` → `socket.getaddrinfo()` → returns the first IP.
* *(observed)* `grid.connectedovals.com resolved to 172.67.210.73 (12 records)`.
* **Why "12 records":** it is really **4 addresses × 3 socket types**. `getaddrinfo` returns one entry each for TCP, UDP and RAW:
  * IPv4 `104.21.61.123`, `172.67.210.73`
  * IPv6 `2606:4700:3034::6815:3d7b`, `2606:4700:3035::ac43:d249`

  These are all **Cloudflare anycast** addresses (104.16.0.0/13, 172.64.0.0/13, 2606:4700::/32), so the origin IP is hidden. Fun detail: the last 32 bits of each IPv6 address encode the IPv4 one (`6815:3d7b` = 0x68.0x15.0x3d.0x7b = 104.21.61.123). Saying this shows you understand IPv6.
* **Manual:**
  ```powershell
  Resolve-DnsName grid.connectedovals.com                 # A + AAAA via your OS resolver
  Resolve-DnsName grid.connectedovals.com -Type AAAA
  Resolve-DnsName grid.connectedovals.com -Server 1.1.1.1 # ask Cloudflare's resolver directly
  Resolve-DnsName connectedovals.com -Type NS             # *.ns.cloudflare.com → Cloudflare is authoritative
  nslookup grid.connectedovals.com 8.8.8.8
  python -c "import socket;[print(i[0].name,i[1].name,i[4][0]) for i in socket.getaddrinfo('grid.connectedovals.com',None)]"
  ```
  The last line reproduces exactly what the keyword does and shows the 12 entries.
* **Where the value comes from:** your OS resolver, which is usually your router, which asks your ISP's resolver (at home that may be Swisscom's DNS). The answer then comes from Cloudflare's authoritative nameservers. Resolver chain: stub → recursive → root → `.com` TLD → authoritative.

#### 3.2 TLS Certificate Is Healthy `[network tls smoke]`
* **Does:**
  1. TCP connect to `:443`.
  2. TLS handshake with **SNI** = hostname. `ssl.create_default_context()` turns on **CA chain verification** (OS/Python trust store) and **hostname verification**.
  3. Reads `notAfter` from the certificate (format `Nov  3 14:35:09 2026 GMT`) and computes the days left.
  4. Fails if fewer than 14 days remain.
* **Manual:**
  * Browser: padlock → *Connection is secure* → *Certificate* → *Issued by*, *Valid to*.
  * Git Bash / Linux / macOS:
    ```bash
    echo | openssl s_client -connect grid.connectedovals.com:443 -servername grid.connectedovals.com 2>/dev/null \
      | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
    ```
  * Pure PowerShell (no openssl needed):
    ```powershell
    $tcp = [Net.Sockets.TcpClient]::new('grid.connectedovals.com', 443)
    $ssl = [Net.Security.SslStream]::new($tcp.GetStream())
    $ssl.AuthenticateAsClient('grid.connectedovals.com')     # SNI + verification
    $c = [Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate
    $c.Subject; $c.Issuer; $c.NotAfter; ($c.NotAfter - (Get-Date)).Days; $ssl.SslProtocol
    $ssl.Dispose(); $tcp.Dispose()
    ```
  * Same as the keyword, in Python:
    ```powershell
    python -c "import ssl,socket;s=ssl.create_default_context().wrap_socket(socket.create_connection(('grid.connectedovals.com',443)),server_hostname='grid.connectedovals.com');c=s.getpeercert();print(c['issuer'],c['notAfter'],s.version())"
    ```
* **What to expect:** a Cloudflare edge certificate (Universal SSL) issued by a public CA such as Google Trust Services or Let's Encrypt. These certs live about 90 days and Cloudflare renews them automatically about 30 days before expiry, which is why 14 days is a safe threshold.
* **Important insight (a strong talking point):** when I ran this suite from a cloud sandbox, the test **passed**, but the certificate's issuer was the sandbox's own **egress proxy CA**, not the real one. The proxy intercepts TLS, and its CA is in that machine's trust store. **The test proves "trusted by this machine", not "this is the real certificate".** A corporate TLS-inspection proxy (common in big companies) would behave the same way. The fix is to also assert the **expected issuer**, or pin the key (see §8).
* **Live failure demo (impressive, takes 20 s).** Point the same test at deliberately broken hosts:
  ```powershell
  robot --outputdir demo --variable HOSTNAME:expired.badssl.com     -t "TLS Certificate Is Healthy" tests/03_network.robot
  robot --outputdir demo --variable HOSTNAME:wrong.host.badssl.com  -t "TLS Certificate Is Healthy" tests/03_network.robot
  robot --outputdir demo --variable MIN_CERT_DAYS:400               -t "TLS Certificate Is Healthy" tests/03_network.robot
  ```
  The first two fail with `Certificate verification FAILED` (expired, hostname mismatch). The third fails the threshold check (`expires in N days minimum requires: 400`). This shows the test can actually go red, which is the point of a negative-path demo.

  > **Rehearse this at home.** In the TLS-intercepting cloud sandbox, the
  > threshold variant failed as expected. Both badssl variants **passed**,
  > because the proxy re-signed them with fresh trusted certificates and hid
  > the expired/mismatched ones. On a normal home connection they fail. On a
  > corporate network with TLS inspection they may not, so use the
  > `MIN_CERT_DAYS:400` variant there. This makes a good story for Q&A.

#### 3.3 HTTPS Port Is Open `[network ports smoke]`
* **Does:** completes a TCP 3-way handshake (SYN → SYN/ACK → ACK) to port 443 within 5 s.
* **Manual:**
  ```powershell
  Test-NetConnection grid.connectedovals.com -Port 443        # TcpTestSucceeded : True, RemoteAddress, latency
  ```
  ```bash
  nc -vz -w 5 grid.connectedovals.com 443
  ```

#### 3.4 Plain HTTP Port Behaviour `[network ports]`
* **Does:** asserts that **port 80 is open**. This is expected, because Cloudflare listens on 80 and redirects to HTTPS.
* **Manual:**
  ```powershell
  Test-NetConnection grid.connectedovals.com -Port 80
  curl.exe -sSI http://grid.connectedovals.com/      # expect 301/308 + Location: https://...
  ```
* **Note:** the test only checks the TCP port. It **doesn't verify the redirect**. Run the `curl` beforehand to see what you actually get. A redirect means "Always Use HTTPS" is on. A 200 over plain HTTP would be a finding.

#### 3.5 Random High Port Is Not Exposed `[network ports negative]`
* **Does:** tries TCP to port **12345** with a 3 s timeout and **passes if the connection fails**.
* *(observed)* `grid.connectedovals.com:12345 is closed/filtered - as expected`.
* **Closed vs filtered:**
  * *Closed*: the host answers with a TCP **RST**, so you see "connection refused" immediately.
  * *Filtered*: packets are **dropped**, so you see a timeout. Cloudflare's edge only listens on specific ports and drops the rest, so this test normally takes about 3 s (the timeout).
* **Manual:**
  ```powershell
  Measure-Command { Test-NetConnection grid.connectedovals.com -Port 12345 }   # ~ False after a wait
  ```
  ```bash
  nc -vz -w 3 grid.connectedovals.com 12345
  nmap -Pn -p 80,443,8080,8443,12345 grid.connectedovals.com    # only scan hosts you own
  ```
* **Cloudflare detail worth knowing:** Cloudflare proxies HTTP on **80, 8080, 8880, 2052, 2082, 2086, 2095** and HTTPS on **443, 2053, 2083, 2087, 2096, 8443**. Port **8080 would be open**, so the docstring example `Port Should Be Closed ... 8080` would actually fail against this host.

---

## 7. Live demo script (pick 2–3 items, about 4 minutes)

Pre-flight (on the day, 30 min before):
1. Open https://grid-qa.connectedovals.com and check the latest nightly is green.
2. Open the GitLab pipelines page and keep one green and **one historic red pipeline** (the lint-gate test) open in tabs.
3. Activate the venv, run `. .\set-env.ps1`, and run the full suite once so pip and DNS caches are warm.
4. Have a **pre-generated `report.html`** ready as a fallback in case the venue Wi-Fi or a corporate proxy blocks you. Corporate networks often block non-standard ports and inspect TLS (see 3.2).

Demo flow:
1. Show the public page → report.html → drill into the network suite.
2. Terminal: `robot --include smoke tests/` (fast and green).
3. Manual proof of one network test: `Resolve-DnsName` + `Test-NetConnection -Port 443` + the cert in the browser padlock. Say: "the robot test does exactly this, automated."
4. **Failure demo:** `--variable HOSTNAME:expired.badssl.com` → red.
5. API: `curl.exe` without `apikey` → 401 live.
6. Show `.gitlab-ci.yml` and explain `|| RESULT=$?` / `exit ${RESULT:-0}` / `when: always`.

---

## 8. Known weaknesses — fix before the presentation, or be ready to explain

Quick fixes (about 1–2 hours total). Colleagues **will** open the repo.

| # | Issue | Where | Fix |
|---|---|---|---|
| 1 | **Typo `ROBBOT_LIBRARY_SCOPE`.** RF ignores it, so the library uses the default *TEST* scope (a new instance per test), not GLOBAL. Harmless today, but a reviewer will spot it. | `NetworkLibrary.py:16` | `ROBOT_LIBRARY_SCOPE = "GLOBAL"` |
| 2 | **`requirements.txt` is UTF-16 LE with CRLF.** Windows PowerShell 5.1 does this with `pip freeze > requirements.txt`. pip copes thanks to the BOM, but `cat`/grep, GitHub's dependency graph and Dependabot don't. | `requirements.txt` | `pip freeze \| Out-File -Encoding utf8 requirements.txt` |
| 3 | **The negative auth test checks "no API key", not "no token"**, but the README claims both. | `02_api.robot:52`, README | Rename to "Request Without Api Key Is Rejected" and add the "key but no token" test (§6, 2.5) |
| 4 | **The RLS test doesn't assert isolation**, only status 200 + count. | `02_api.robot:41` | Assert that every row's `user_id` == `sub` from the login response (`$login.user.id`) |
| 5 | **Test dependency:** if login fails, the RLS test fails with "variable not found" rather than a clear message. | `02_api.robot:38` | Get the token in the Suite Setup, or `Skip If` no token |
| 6 | **Lint only covers `libraries/`.** `scripts/make_index.py` currently **fails** `ruff format --check` (a double space in `failed ==  0`). | `.gitlab-ci.yml:11-12` | `ruff check .` + `ruff format --check .`, and run `ruff format scripts/` |
| 7 | Port 80 test doesn't check the redirect | `03_network.robot:30` | Add an HTTP test: `GET http://… allow_redirects=False` → 301/308 + `Location: https://` + an `Strict-Transport-Security` header on HTTPS |
| 8 | Wrong docstring example (8080 is open on Cloudflare) | `NetworkLibrary.py:94` | Use 12345 |
| 9 | Typos: "netowork", "connecteedovals", "leasy", "recieve", "stpops", "iindex", trailing `\` in module docstring | various | Proofread |
| 10 | `README → Running locally` is a placeholder | README | Write the actual commands (§6.0) |
| 11 | `public/index.html` is committed but is generated output (stale 13/13 from Aug 9) | repo | Add `public/` to `.gitignore` and remove it from git |
| 12 | Unused shared keyword `Log Test Context`; `01_smoke` repeats the URL instead of using `${BASE_URL}` | resource / smoke | Use it in the suites or remove it |
| 13 | `publish` has no branch rule, so any branch pipeline deploys | `.gitlab-ci.yml:33` | `rules: - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` |
| 14 | DNS "12 records" log is misleading | `NetworkLibrary.py:30` | Log unique IPs: `sorted({i[4][0] for i in infos})` |

> If you only have time for a few, do **1, 2, 3, 6 and 9**. They're cheap and
> they're what a reviewer notices first.

Also be ready for this one. **Protected variables:** if the GitLab variables
are marked *protected*, they only exist on protected branches. A feature-branch
pipeline would then see missing env vars. In `--dryrun` they only print
`[ ERROR ]` lines and don't fail the run (verified), but the live API tests
would fail.

---

## 9. Improvement roadmap (good "what's next" slide)

**Network-QA depth (most relevant for Swisscom):**
* **IPv6 first-class:** assert that AAAA records exist and that 443 is reachable **over IPv6** (`socket.AF_INET6`). Swisscom runs a dual-stack network with heavy IPv6 use.
* **DNS:** query several resolvers and compare answers (dnspython). Check DNSSEC validation, **CAA records** (which CAs may issue certs), and NS/TTL.
* **TLS hardening:** reject TLS 1.0/1.1, check the negotiated protocol and cipher, **expected issuer / pin**, HSTS, OCSP stapling.
* **HTTP:** security headers (HSTS, CSP, X-Content-Type-Options), redirect chain, response-time thresholds (SLOs, e.g. p95 < 500 ms).
* **Latency/path:** keywords for ping/RTT and traceroute, MTU/PMTUD checks.
* **Real network devices:** RF + **SSHLibrary / Netmiko / NAPALM / pyATS** against a virtual lab (**containerlab** with FRR/SR Linux routers). For example, test that BGP/OSPF neighbours come up, that routes are present, and that a config change doesn't break reachability. This is the natural next step from "test a web app's network edge" to "test the network itself", and the strongest bridge to a network QA job.
* **SNMP / NETCONF / gNMI** telemetry assertions.

**DevOps / CI maturity:**
* Build a **custom Docker image** with dependencies pre-installed (stored in the GitLab Container Registry), or add `cache:` for pip, to make jobs faster.
* **pabot** for parallel runs. Tag-based pipelines: `--include smoke` on every push, the full suite nightly.
* **pytest unit tests for NetworkLibrary** with mocked sockets. Tests for your test code are a mark of seniority.
* **pre-commit** hooks (ruff) so lint errors never reach CI.
* **Notifications:** failed nightly → Slack/Teams/e-mail (webhook in an `after_script` or a separate `when: on_failure` job).
* **Trend history:** keep the last N `output.xml` files and chart the pass rate and cert-days-left over time. Or push metrics to **Prometheus Pushgateway + Grafana**, which turns tests into monitoring.
* **Infrastructure as Code:** manage Cloudflare DNS/Pages with **Terraform**, and test the plan in CI.
* **Secrets:** HashiCorp Vault / GitLab OIDC instead of long-lived variables, and rotate the test-user password.
* **Load/performance testing:** k6 or Locust against a staging environment, never against prod without limits.
* **Staging environment:** a second Supabase project so destructive tests (create/update/delete habit) can run safely.

---

## 10. Suggested structure for 12 minutes

| Min | Content |
|---|---|
| 0–1 | Who I am + elevator pitch (§0) |
| 1–2 | System under test: Grid, Cloudflare in front, Supabase behind (diagram §2) |
| 2–4 | Stack + why (§1), RF syntax in 30 s with one keyword from NetworkLibrary on screen |
| 4–8 | **Tests by layer:** network (DNS/TLS/ports + closed vs filtered), API/auth (JWT, RLS, negative 401) |
| 8–10 | Live demo (§7): manual check ↔ robot test, badssl failure |
| 10–11 | Pipeline: lint gate story (red → green), honest-fail/always-publish, sanitised report |
| 11–12 | Lessons learned + roadmap (§9): IPv6, device testing with containerlab, monitoring |
| + | Q&A |

---

## 11. Likely questions and good answers

* **Why Robot Framework and not pytest?** Keyword-driven tests read like specifications, so non-developers can review them. It came out of Nokia Networks and is common in telecom. I can still write Python where needed, as `NetworkLibrary` shows. Under the hood it's all Python.
* **Why test production?** It's a single-person project with no staging environment. The tests are **read-only** and use a dedicated test user. Next step: a staging project for write tests.
* **How do you handle secrets?** Environment variables locally (a git-ignored `set-env.ps1`) and masked GitLab CI/CD variables in the pipeline. I only log the token *length*. `log.html` isn't published. The anon key is public by design, and RLS is the real security boundary.
* **What's the difference between 401 and 403?** 401 means unauthenticated (we don't know who you are). 403 means authenticated but not allowed.
* **What does RLS do?** Postgres filters every query with a policy such as `user_id = auth.uid()`, using the user id from the JWT. So even if the API is called directly, a user only sees their own rows.
* **Closed vs filtered port?** RST (refused, immediate) vs a silent drop (timeout). Firewalls and Cloudflare usually drop.
* **What happens if DNS is down in CI?** All network/API tests fail. That's correct behaviour, but it would be useful to tell infrastructure failures apart from product failures (tags, or a dedicated pre-check that skips the rest).
* **Why does the job fail but still publish?** `|| RESULT=$?` delays the failure, `artifacts: when: always` keeps the outputs, and `publish: when: always` deploys them. Visibility is the point of a nightly job.
* **How would you test a router/switch?** RF + SSHLibrary/Netmiko: connect, run `show` commands, parse them (TextFSM/Genie), assert neighbour states and routes. Run it against a containerlab topology in CI before touching real devices.
* **Flaky tests?** The network can flake. Use sensible timeouts (already set: 3–10 s) and possibly one retry for network tests only, but never hide real failures. Track the flake rate over time.
* **Where does SNI come in?** Many sites share one Cloudflare IP. SNI in the TLS ClientHello tells the server which certificate to present. Without `server_hostname=` you'd get the wrong certificate or a handshake failure.
* **What does the TLS test NOT prove?** That this is the *genuine* certificate. A TLS-intercepting proxy with a locally trusted CA passes it (I saw this happen in a sandbox). The fix is an issuer assertion or pinning.

---

## 12. Glossary (one-liners)

* **Anycast:** the same IP is announced from many locations, and BGP routes you to the nearest. This is how Cloudflare's 104.21.x / 172.67.x addresses work.
* **SNI:** Server Name Indication, the hostname sent in the TLS ClientHello.
* **CA chain:** leaf cert → intermediate → root that is trusted by the OS.
* **notAfter:** the certificate's expiry timestamp.
* **JWT:** a signed token in the form `header.payload.signature`. Its claims include `sub`, `role` and `exp`.
* **PostgREST:** automatic REST API over Postgres. **GoTrue:** Supabase's auth server.
* **RLS:** Row-Level Security in Postgres.
* **JUnit/xUnit XML:** the standard test-result format CI tools understand.
* **Artifact:** files a CI job saves and passes to later jobs or makes available for download.
* **Rebot:** RF tool that turns `output.xml` into reports without re-running tests.
* **Dry run:** parse and resolve keywords without executing them.
