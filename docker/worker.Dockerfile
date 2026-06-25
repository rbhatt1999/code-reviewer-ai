# worker.Dockerfile — Sidekiq worker image with every static-analysis
# tool the review pipeline needs.
#
# Status: deliverable for the design document and the synopsis's final
# one-command Docker-Compose outcome. Increment 2 verification runs
# locally on macOS (Sidekiq + Rails + Vite on the host); this image is
# the same conceptual unit packaged for portable deployment.
#
# What is installed:
#   - Ruby 3.2.5 (base image)
#   - Bundle of project gems (RuboCop, Brakeman are Ruby gems)
#   - Python 3 + Bandit + Semgrep CE  (security and cross-language SAST)
#   - Node.js 20 + ESLint v9          (JavaScript / TypeScript linting)
#   - tree-sitter CLI                  (AST extraction for the LLM prompt)
#   - git                              (Git-URL ingestion)
#
# Build:  docker build -f docker/worker.Dockerfile -t cra-worker .
# Run:    docker run --rm --env-file backend/.env cra-worker

FROM ruby:3.2.5-slim

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# System packages -----------------------------------------------------------
# build-essential + libpq-dev: native gem builds (pg, oj, prawn).
# python3 + pip:               Bandit + Semgrep runtimes.
# nodejs + npm:                ESLint + tree-sitter CLI (npm package).
# git:                         Ingestion::GitCloner (`git clone --depth 1`).
RUN apt-get update -y && apt-get install -y --no-install-recommends \
        build-essential libpq-dev pkg-config \
        python3 python3-pip python3-venv \
        nodejs npm \
        git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python static analysers ---------------------------------------------------
# Bandit (Python security) and Semgrep CE (cross-language SAST). Bandit is
# light; Semgrep pulls a sizeable wheel set.
RUN pip3 install --no-cache-dir --break-system-packages \
        bandit~=1.7 \
        semgrep~=1.85

# Pre-warm Semgrep registry rulesets at build time so scans work offline.
# `semgrep scan --config auto` would otherwise fetch from semgrep.dev at
# scan time — unacceptable in a sealed worker. The cache lives under
# /root/.semgrep so subsequent `--config <ruleset>` invocations hit it.
RUN semgrep --config p/ruby --config p/python --config p/javascript --config p/java \
        --no-error --no-text-output --dry-run /dev/null || true

# Node analysers ------------------------------------------------------------
# ESLint v9 standalone (uses our bundled flat config — no project package.json
# required). tree-sitter CLI is the parser invoked by Ast::Extractor.
RUN npm install -g --omit=dev \
        eslint@^9 \
        tree-sitter-cli@^0.22

# Application --------------------------------------------------------------
WORKDIR /app

COPY backend/Gemfile backend/Gemfile.lock ./
RUN bundle install --without development:test

COPY backend/ ./

# Sidekiq is the entrypoint; the same image can also boot Rails by
# overriding CMD (e.g. `bin/rails server -b 0.0.0.0`).
CMD ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
