# CodeReviewer.AI

A self-hosted, open-source LLM-powered code review assistant built on Ruby on Rails and React.
It ingests source code or pull-request diffs, runs a hybrid analysis pipeline (classical
static analysis + a locally-served open-source code LLM via Ollama), and returns structured,
line-anchored review feedback — with **zero paid APIs**.

> MCA Major Project (23ONMCR-753) — Rohit Bhatt, UID O24MCA111733, Chandigarh University CDOE.

## Tech stack

| Layer | Technology |
|---|---|
| Backend | Ruby 3.2, Rails 7.1 (API mode) |
| Frontend | React 18, TypeScript 5, Vite |
| Database | PostgreSQL 15 |
| Background jobs | Sidekiq 7 + Redis |
| Auth | Devise + devise-jwt |
| LLM runtime | Ollama (Qwen2.5-Coder-7B-Instruct) |
| Static analysis | RuboCop, ESLint, Brakeman, Bandit, Semgrep CE |
| Testing | RSpec, Jest, Cypress |

## Repository layout

```
backend/    Rails 7.1 API-only application
frontend/   React 18 + TypeScript + Vite SPA
docker-compose.yml   Full stack: Postgres, Redis, Rails API, Sidekiq worker, React SPA
```

## Run it — one command via Docker

The entire stack (Postgres, Redis, the Rails API, a Sidekiq worker, and the React
SPA) runs from `docker-compose.yml`. Two commands total — one to build, one to start:

```bash
# 1. Build the images (only needed the first time, or after changing code/Gemfile/package.json)
docker compose build

# 2. Start everything
docker compose up
```

That's it:
- API: http://localhost:3000
- Frontend: http://localhost:5173
- Postgres: localhost:5432, Redis: localhost:6379

The backend container runs `db:prepare` + `db:seed` on every start (seeding is
idempotent), so the database is always ready — no separate migrate step. Seed
users: `admin@example.com` / `demo@example.com`, password `password1234`.

`backend/.env` already carries the DeepSeek API key, so no local Ollama server
is needed. To rebuild after a code change: `docker compose up --build`. To stop:
`docker compose down` (add `-v` to also wipe the Postgres/Redis volumes).

### Exposing the webhook publicly for a demo (ngrok)

GitHub's servers can't reach `http://localhost:3000` — it only exists on your
machine. To let a real GitHub webhook hit your local backend during a demo,
tunnel it through ngrok:

```bash
# 1. Free account → https://dashboard.ngrok.com/signup, then grab your
#    authtoken from https://dashboard.ngrok.com/get-started/your-authtoken
export NGROK_AUTHTOKEN=<your token>          # or add it to backend/.env

# 2. Start the stack + the tunnel (the "demo" profile is opt-in, see below)
docker compose --profile demo up
```

Once it's up, open **http://localhost:4040** — ngrok's local inspector shows
your current public URL (something like `https://a1b2c3d4.ngrok-free.app`)
and lets you replay/debug each incoming webhook delivery.

In the project's webhook panel (`/projects/:id` in the app), use that ngrok
URL instead of the localhost one when you configure the webhook in GitHub —
`https://a1b2c3d4.ngrok-free.app/api/v1/webhooks/github`, content type
`application/json`, event: **Pull requests** only. Copy the secret shown in
the same panel into GitHub's "Secret" field.

Free-tier ngrok URLs change every time you restart the tunnel, so re-check
http://localhost:4040 and update the GitHub webhook's Payload URL if you
stop and restart between demo runs.

### Manual (non-Docker) setup

Useful for active backend/frontend development with faster reload:

```bash
# 1. Data stores only
docker compose up -d postgres redis

# 2. Backend
cd backend
bundle install
cp ../.env.example ../.env             # then fill in secrets (bin/rails secret)
bin/rails db:create db:migrate db:seed
bin/rails server -p 3000

# 3. Sidekiq worker
cd backend
bundle exec sidekiq -C config/sidekiq.yml

# 4. Frontend (Node 20)
cd frontend
npm install
npm run dev                            # http://localhost:5173
```

### Increment 2 local toolchain (one-time)

The async pipeline shells out to five static analysers. Install them on the host
machine — they are not Ruby gems:

```bash
# Node (ESLint v9 — runs against the bundled flat config under app/services/runners/)
npm install -g eslint@^9

# Python (Bandit + Semgrep CE)
pipx install bandit
brew install semgrep            # or: pipx install semgrep

# Tree-sitter CLI (AST extraction; falls back to no-op if absent)
brew install tree-sitter
```

The Sidekiq pipeline is robust to a missing analyser — it logs and continues, the
submission still reaches `completed`. The same toolchain, packaged for portable
deployment, lives in `docker/worker.Dockerfile`.

### Port 3000 must be free for the WebSocket

Increment 2 introduces ActionCable. The frontend's `VITE_API_BASE_URL` and
`VITE_WS_BASE_URL` both point at `localhost:3000`; before starting the dev servers
either free TCP `:3000` or run Rails on another port AND update both `VITE_*` env
vars in `frontend/.env` to match. With a mismatched port the WebSocket silently
fails and the live status badge never updates.

## Tests

```bash
bin/ci                  # runs RSpec + Jest
cd backend  && bundle exec rspec
cd frontend && npm test
```

## SDLC

Iterative-Incremental, 4 increments over 14 weeks.
- **Increment 1** — authentication, project CRUD, single-file upload, RuboCop runner (synchronous).
- **Increment 2** — async Sidekiq pipeline, AASM state machine, ActionCable live status, four more analysers (ESLint / Brakeman / Bandit / Semgrep), ZIP + Git-URL ingestion, Tree-sitter AST.
- **Increment 3** — Ollama LLM integration, hybrid linter+LLM aggregation, diff viewer.
- **Increment 4** — report export, GitHub webhook, admin dashboard, 90-case evaluation, documentation.
