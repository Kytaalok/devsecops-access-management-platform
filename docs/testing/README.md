# Документация по тестированию

В этой директории находятся материалы для главы 6 ВКР и для практической фиксации результатов испытаний.

## Файлы

- `test-plan.md` — методика комплексного тестирования.
- `test-protocol.md` — протокол тестирования с перечнем проверок и ожидаемыми результатами.
- `artifacts/` — переносимые результаты запусков тестов и CI/CD, пригодные для приложений ВКР.

## Уровни тестирования

- Локальные тесты API: `pytest`-проверки бизнес-логики Task Manager API.
- Интеграционные smoke-тесты: проверка frontend, API, Keycloak, Jenkins и PostgreSQL на развернутом стенде.
- RBAC-тесты: положительные и отрицательные проверки авторизации в API и Kubernetes.
- Тесты CI/CD-безопасности: Gitleaks, Semgrep, Trivy FS scan и Trivy image scan.

## Команды

Запуск локальных тестов API:

```bash
cd services/task-manager-api
pytest -q
```

Запуск локальных тестов API с JUnit-отчётом:

```bash
cd services/task-manager-api
mkdir -p ../../docs/testing/artifacts
PYTHONPATH="$PWD" python -m pytest -q --junitxml=../../docs/testing/artifacts/api-pytest.xml
```

Запуск проверок развернутого стенда:

```bash
./infra/scripts/bootstrap_keycloak_and_smoke_test.sh
```

Запуск Jenkins pipeline:

```text
Jenkins -> Pipeline -> Build with Parameters
```
