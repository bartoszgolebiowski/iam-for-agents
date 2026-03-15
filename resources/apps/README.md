# Demo Resource Servers (TODO + NOTES)

Two basic Node.js CRUD apps with Docker and authorization based on shared Keycloak groups.

## Services

- TODO app: port 3001
- NOTES app: port 3002
- Orchestrator app: port 3003

## Start

```bash
cd resources/apps
docker compose up --build -d
```

Then open:

- http://localhost:3003

## Authorization model

Both services read groups from one source of truth:

- `resources/keycloack/configuration/groups.yaml`

The file is mounted read-only into both containers as `/app/config/groups.yaml`.

Request user identity is taken from:

- `x-user` header (preferred)
- or `?user=<username>` query parameter

Server checks existing groups only (no extra groups created):

- TODO permissions: `TODO_READ`, `TODO_WRITE`
- NOTES permissions: `NOTES_READ`, `NOTES_WRITE`
- Project scope: `PROJECT_HR`, `PROJECT_FIN`, `PROJECT_OPS`, `PROJECT_SALES`

Every TODO/NOTES operation requires app permission and project membership.

## Quick examples

### TODO app

```bash
curl -H "x-user: alice" http://localhost:3001/projects
curl -H "x-user: alice" -H "Content-Type: application/json" \
  -d '{"title":"Prepare demo","projectId":1}' \
  http://localhost:3001/todos
curl -X DELETE -H "x-user: bob" http://localhost:3001/todos/1
```

The delete call above should return `403` because `bob` is `TODO_WRITE`, but this sample todo may be outside his allowed project scope.

### NOTES app

```bash
curl -H "x-user: bob" http://localhost:3002/notes
curl -H "x-user: bob" -H "Content-Type: application/json" \
  -d '{"title":"API notes","content":"v1 endpoints","projectId":1}' \
  http://localhost:3002/notes
curl -X PUT -H "x-user: diana" -H "Content-Type: application/json" \
  -d '{"title":"updated"}' \
  http://localhost:3002/notes/1
```

The last call should return `403` because `diana` has read-only rights in NOTES app.

## Orchestrator flow

The orchestrator provides a simple UI with three steps:

1. Login against Keycloak and store access token in session.
2. Exchange token for NOTES audience.
3. Click Get Notes Data button to fetch `/notes` from NOTES API.

Configuration comes from:

- `orchestrator-app/config/orchestrator.yaml`

Main config values:

- Keycloak URL, realm, token endpoint
- Orchestrator client ID and secret
- NOTES audience for token exchange
- NOTES API base URL
