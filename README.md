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
docker-compose.yml   PostgreSQL + Redis (data stores)
```

## Development setup

```bash
# 1. Data stores
docker compose up -d postgres redis    # or: brew services start postgresql@15 redis

# 2. Backend
cd backend
bundle install
cp ../.env.example ../.env             # then fill in secrets (bin/rails secret)
bin/rails db:create db:migrate db:seed
bin/rails server -p 3000

# 3. Sidekiq worker  (Increment 2+)
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
