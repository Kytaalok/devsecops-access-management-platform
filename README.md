# Diplom DevSecOps Platform

Monorepo for diploma project:
"Centralized user and role management in a DevSecOps infrastructure".

## Planned structure

- `services/task-manager-api` - test application for IAM verification.
- `infra/` - Kubernetes manifests, Helm charts, ingress, environment setup.
- `cicd/` - Jenkinsfiles, pipeline shared scripts, security scan configs.
- `docs/` - thesis assets, diagrams, test protocols.

## Why monorepo for this diploma

- One owner and one delivery stream.
- Tight coupling between app, IAM, CI/CD, and infrastructure.
- Easier traceability of architecture decisions and results in commit history.

