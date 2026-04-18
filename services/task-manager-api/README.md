# Task Manager API

Тестовое приложение для проверки интеграции IAM в рамках дипломного стенда.

## Возможности (этап 1)

- Endpoint для проверки состояния сервиса.
- CRUD-операции для задач.
- Endpoint `/me` для получения данных текущего пользователя.
- Ролевой контроль доступа (`admin`, `developer`, `viewer`).
- Подготовленный слой JWT-аутентификации для интеграции с Keycloak.
- Модели SQLAlchemy и сессия БД.
- Dockerfile для сборки контейнера.

## Локальный запуск

1. Создать виртуальное окружение и установить зависимости.
2. Скопировать `.env.example` в `.env` и задать значения переменных.
3. Запустить API:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Маршруты API

- `GET /health`
- `GET /me`
- `GET /tasks`
- `POST /tasks`
- `GET /tasks/{task_id}`
- `PUT /tasks/{task_id}`
- `DELETE /tasks/{task_id}`

## Режимы аутентификации

- `AUTH_ENABLED=false` (по умолчанию): режим разработки, данные пользователя читаются из заголовков.
- `AUTH_ENABLED=true`: API ожидает `Authorization: Bearer <JWT>` и валидирует токен через Keycloak JWKS.

Заголовки для режима разработки:

- `X-User-Id`
- `X-Username`
- `X-Email`
- `X-Role` (`admin`, `developer`, `viewer`)
