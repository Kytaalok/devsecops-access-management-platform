# Assets for appendices

This directory is intended for raw artifacts used in diploma appendices.

Recommended files to collect:

```text
pytest.log
smoke-test.log
jenkins-build-log.txt
jenkins-stage-view.png
gitleaks.sarif
semgrep.json
trivy-fs.sarif
trivy-image-api.sarif
trivy-image-frontend.sarif
grafana-security-events-dashboard.json
grafana-security-events-dashboard.png
```

Useful commands on the stand:

```bash
cd services/task-manager-api
pytest -q | tee ../../docs/appendices/assets/pytest.log
```

```bash
./infra/scripts/bootstrap_keycloak_and_smoke_test.sh \
  | tee docs/appendices/assets/smoke-test.log
```

Grafana dashboard JSON is exported from the Grafana UI:

```text
Dashboard -> Share -> Export -> Save to file
```

Jenkins artifacts are downloaded from the completed build page:

```text
Build -> Artifacts
Build -> Console Output
Pipeline -> Stage View
```
