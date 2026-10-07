# grid-qa
[![pipeline status](https://gitlab.com/vlads-lavrenovs-group/grid-qa/badges/main/pipeline.svg)](https://gitlab.com/vlads-lavrenovs-group/grid-qa/-/pipelines)

Automated test suite for my production habit-tracker **Grid**
(https://grid.connectedovals.com) — Robot Framework + custom Python
keyword libraries, executed nightly by GitLab CI, results published to
**https://grid-qa.connectedovals.com**.

## What it tests
- API & auth behaviour of the live app (Supabase):
  - login flow (email/password test user)
  - RLS ownership: every row returned to the test user must have its user_id
  - cross-user isolation: user A cannot read a known row owned by user B
  - anon key without a user token sees no rows (200 + empty list)
  - request without an API key is rejected by the gateway (401)
- Network layer: DNS resolution, TLS certificate validity window,
  port exposure (incl. negative checks)
- Toolchain smoke tests

## How it works
![Diagram](/assets/Readme-diagram.png)

lint (ruff + RF dryrun) → test (live suite, artifacts) → publish
(rebot-sanitized report + generated summary page → Cloudflare Pages)

## Design decisions
- Execution log (log.html) is deliberately NOT published — request-level
  data stays in private CI artifacts; the public site gets a rebot-built
  report without it.
- Suite fails honestly (exit-code capture) while reporting always publishes —
  a red night is visible by design.
- Dedicated email/password test user because OAuth isn't automatable
  server-side; secrets injected via env vars locally / masked CI variables.
- Credentials and tokens are suppressed from Robot logs, and CI artifacts are
  restricted to project members.

## Running locally
[venv, requirements, env vars via a local gitignored script (set-env.ps1 on
Windows / set-env.sh on Linux; values not included), robot command]

## Stack
Robot Framework · Python 3.12 · RequestsLibrary · ruff · GitLab CI ·
Cloudflare Pages · Supabase (system under test)