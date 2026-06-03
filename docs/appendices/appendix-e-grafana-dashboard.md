# Приложение Д. JSON дашборда событий безопасности Grafana

В репозитории на момент оформления отсутствует экспортированный JSON дашборда Grafana. После настройки Grafana его нужно выгрузить из интерфейса Grafana: `Dashboard -> Share -> Export -> Save to file`.

Рекомендуемое имя файла в репозитории:

```text
docs/appendices/assets/grafana-security-events-dashboard.json
```

После экспорта в приложение следует вставить JSON в таком виде:

```json
{
  "title": "Security Events Dashboard",
  "panels": []
}
```

Что должно быть отражено на дашборде:

- события входа и ошибок аутентификации Keycloak;
- события отказа доступа `401` и `403` в Task Manager API;
- события Jenkins pipeline и результаты security stages;
- агрегированные показатели по ролям `admin`, `developer` и `viewer`;
- временная шкала событий безопасности.
