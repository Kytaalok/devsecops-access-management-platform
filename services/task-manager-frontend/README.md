# Task Manager Frontend

Веб-интерфейс для `Task Manager API`, предназначенный для демонстрации:

- ролевой модели (`admin`, `developer`, `viewer`);
- проверки доступа к endpoint'ам;
- базового управления задачами через REST API.

## Что реализовано

- адаптивный интерфейс с доской задач по статусам;
- просмотр текущего пользователя через `GET /me`;
- создание, изменение и удаление задач;
- переключение режима авторизации:
- `Dev headers` (`X-User-Id`, `X-Username`, `X-Email`, `X-Role`);
- `Bearer token` (JWT).

## Локальный запуск

Можно открыть как статический сайт любым сервером статики, например:

```bash
python -m http.server 8081
```

После запуска открой:

- `http://localhost:8081`

В интерфейсе укажи `Base URL` API, например:

- `http://localhost:8000`

## Запуск в контейнере

```bash
docker build -t task-manager-frontend .
docker run --rm -p 8081:80 task-manager-frontend
```

## Важно для CORS

Если фронтенд и API работают на разных origin, в API должен быть разрешён CORS.
В `task-manager-api` для этого добавлена переменная:

- `CORS_ALLOW_ORIGINS=*`

Для production рекомендуется указать конкретные домены вместо `*`.

