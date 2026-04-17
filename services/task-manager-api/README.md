# Task Manager API

Test application for verifying IAM integration in the diploma stand.

## Features (step 1)

- Health endpoint.
- CRUD for tasks.
- `/me` endpoint for current user context.
- Role-based access control (`admin`, `developer`, `viewer`).
- JWT auth dependency prepared for Keycloak integration.
- SQLAlchemy models and DB session.
- Dockerfile for container build.

## Local run

1. Create venv and install dependencies.
2. Copy `.env.example` to `.env` and adjust values.
3. Start API:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API routes

- `GET /health`
- `GET /me`
- `GET /tasks`
- `POST /tasks`
- `GET /tasks/{task_id}`
- `PUT /tasks/{task_id}`
- `DELETE /tasks/{task_id}`

## Auth behavior

- `AUTH_ENABLED=false` (default): development mode, user context is read from headers.
- `AUTH_ENABLED=true`: API expects `Authorization: Bearer <JWT>` and validates token against Keycloak JWKS.

Development headers:

- `X-User-Id`
- `X-Username`
- `X-Email`
- `X-Role` (`admin`, `developer`, `viewer`)
