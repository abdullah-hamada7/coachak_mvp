# Coachak MVP

AI-powered fitness coaching platform with personalized workout/nutrition plans, conversational AI coach, on-device form analysis, food recognition, and gamification.

## Architecture

- **Mobile**: Flutter 3 + Riverpod + GoRouter (`apps/mobile`)
- **API**: FastAPI + LangGraph + Gemini (`services/api`)
- **Data**: PostgreSQL 16 + pgvector, Redis
- **Knowledge**: Curated fitness corpus (`packages/fitness-knowledge`)

## Quick Start

### Infrastructure

Start PostgreSQL, Redis, and the API locally:

```bash
cd infra
docker compose up -d
```

The mobile app defaults to `http://127.0.0.1:8000`. Override with `--dart-define=API_BASE_URL=...` or `apps/mobile/env/dev.json` / `env/prod.json`.

### API

```bash
cd services/api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # set GEMINI_API_KEY, JWT_SECRET
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Mobile

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Eval

```bash
cd eval
python -m pytest tests/ -v
```

## Environment Variables

See `services/api/.env.example`.

## Secrets and Configuration

- Keep real secrets in local `.env` files or your CI secret manager.
- Never commit real API keys, tokens, or certificates.
- The repository includes a local pre-commit hook in `.githooks/pre-commit` to block obvious secret leaks before commit.

## API Docs

http://localhost:8000/docs

## Subscription Plans

See [docs/SUBSCRIPTION_PLANS.md](docs/SUBSCRIPTION_PLANS.md) for EGP pricing tiers, feature matrix, product IDs, and API usage limits.
