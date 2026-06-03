# Протокол тестирования

## Объект тестирования

Система централизованного управления пользователями и ролями в DevSecOps-инфраструктуре.

## Тестовая среда

| Параметр | Значение |
| --- | --- |
| Кластер | k3s |
| Namespace приложения | `task-manager-api` |
| Namespace CI/CD | `cicd` |
| Поставщик удостоверений | Keycloak |
| Backend | FastAPI, SQLAlchemy |
| База данных | PostgreSQL |
| CI/CD | Jenkins |
| Инструменты безопасности | Gitleaks, Semgrep, Trivy |

## Тестовые сценарии

| ID | Проверка | Команда или действие | Ожидаемый результат | Фактический результат |
| --- | --- | --- | --- | --- |
| TC-01 | Локальные тесты API | `cd services/task-manager-api && pytest -q` | Все тесты пройдены | Заполнить после запуска |
| TC-02 | Тесты API в Jenkins | Stage `API Unit Tests` | JUnit-отчет опубликован, stage успешен | Заполнить после запуска |
| TC-03 | Доступность frontend | `curl -i $FRONTEND_URL/` | `HTTP 200` | Заполнить после запуска |
| TC-04 | Health-check API | `curl -i $API_URL/health` | `HTTP 200`, тело `{"status":"ok"}` | Заполнить после запуска |
| TC-05 | OIDC discovery Keycloak | `curl -i $KEYCLOAK_URL/realms/devsecops/.well-known/openid-configuration` | `HTTP 200` | Заполнить после запуска |
| TC-06 | Страница входа Jenkins | `curl -i $JENKINS_URL/login` | `HTTP 200` | Заполнить после запуска |
| TC-07 | Запрос без авторизации | `curl -i $API_URL/me` | `HTTP 401` | Заполнить после запуска |
| TC-08 | Профиль admin | Токен `admin1`, запрос `/me` | `HTTP 200`, роль `admin` | Заполнить после запуска |
| TC-09 | Профиль developer | Токен `dev1`, запрос `/me` | `HTTP 200`, роль `developer` | Заполнить после запуска |
| TC-10 | Профиль viewer | Токен `viewer1`, запрос `/me` | `HTTP 200`, роль `viewer` | Заполнить после запуска |
| TC-11 | Viewer не может создать задачу | `POST /tasks` с viewer token | `HTTP 403` | Заполнить после запуска |
| TC-12 | Admin может создать задачу | `POST /tasks` с admin token | `HTTP 201` | Заполнить после запуска |
| TC-13 | Developer может создать задачу | `POST /tasks` с developer token | `HTTP 201` | Заполнить после запуска |
| TC-14 | Developer может изменить свою задачу | `PUT /tasks/{id}` с токеном владельца | `HTTP 200` | Заполнить после запуска |
| TC-15 | Viewer не может изменить задачу | `PUT /tasks/{id}` с viewer token | `HTTP 403` | Заполнить после запуска |
| TC-16 | Проверка PostgreSQL | `select 1` внутри PostgreSQL pod | Результат `1` | Заполнить после запуска |
| TC-17 | Права admin в Kubernetes | `kubectl auth can-i get nodes` с admin OIDC token | `yes` | Заполнить после запуска |
| TC-18 | Ограничение developer | `kubectl auth can-i get secrets -n task-manager-api` с developer OIDC token | `no` | Заполнить после запуска |
| TC-19 | Чтение для viewer | `kubectl auth can-i get pods -n task-manager-api` с viewer OIDC token | `yes` | Заполнить после запуска |
| TC-20 | Запрет записи для viewer | `kubectl auth can-i create deployments -n task-manager-api` с viewer OIDC token | `no` | Заполнить после запуска |
| TC-21 | Jenkins OIDC redirect | Вход в Jenkins через OIDC | Перенаправление на endpoint авторизации Keycloak | Заполнить после запуска |
| TC-22 | Gitleaks scan | Stage `Gitleaks` | Секреты не найдены либо build завершен ошибкой при обнаружении | Заполнить после запуска |
| TC-23 | Semgrep scan | Stage `Semgrep` | Отчет архивирован, политика зависит от `SEMGREP_STRICT` | Заполнить после запуска |
| TC-24 | Trivy filesystem scan | Stage `Trivy FS` | SARIF-отчет архивирован | Заполнить после запуска |
| TC-25 | Trivy image scan | Stage `Image Scan` | SARIF-отчеты для API и frontend архивированы | Заполнить после запуска |
| TC-26 | Rollout после деплоя | Stage `Rollout Check` | Deployment API и frontend успешно обновлены | Заполнить после запуска |

## Сводная автоматическая проверка

Основной интеграционный протокол запускается командой:

```bash
./infra/scripts/bootstrap_keycloak_and_smoke_test.sh
```

Формат успешного результата:

```text
==================== RESULT ====================
Passed: <number>
Failed: 0
================================================
```

## Итог

Испытания считаются успешными, если все обязательные проверки завершаются без ошибок, а Jenkins pipeline архивирует отчеты безопасности как артефакты сборки.
