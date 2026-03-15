# Keycloak Configuration Reference

This directory contains YAML configuration files for Keycloak setup.

## Files

- **`users.yaml`** – User accounts with credentials and attributes
- **`groups.yaml`** – Group definitions and group membership (single source of truth for authorization)
- **`clients.yaml`** – OAuth2 clients, scopes, and token exchange policies

## clients.yaml Structure

### Scopes

OAuth2 scopes that define granular permissions:
- `todo.read`, `todo.write`, `todo.admin` – TODO app scopes
- `notes.read`, `notes.write`, `notes.admin` – NOTES app scopes
- `profile`, `email` – Standard OpenID Connect scopes

### Clients

Three main clients are defined:

#### 1. orchestrator-app
- **Type**: Confidential client (has secret)
- **Flow**: Authorization code + resource owner password
- **Purpose**: Web UI that initiates login and performs token exchange
- **Client ID**: `orchestrator-app`
- **Client Secret**: `orchestrator-secret`
- **Token Exchange**: Can exchange tokens for `todo-app` and `notes-app` audiences

#### 2. todo-app
- **Type**: Bearer-only client (cannot request tokens directly)
- **Purpose**: Resource server that validates Bearer tokens
- **Client ID**: `todo-app`
- **Client Secret**: `todo-app-secret`
- **Audience**: `todo-app` (used in token exchange target)

#### 3. notes-app
- **Type**: Bearer-only client (cannot request tokens directly)
- **Purpose**: Resource server that validates Bearer tokens
- **Client ID**: `notes-app`
- **Client Secret**: `notes-app-secret`
- **Audience**: `notes-app` (used in token exchange target)

### Protocol Mappers

Each client has mappers that add claims to issued tokens:
- `username` (preferred_username) – Extracted from user attributes
- `email` – User email address
- `groups` – Array of group names user belongs to (multi-valued)
- `audience` – Identifies the resource server

### Token Exchange Policies

Defines which clients can exchange tokens for which audiences:
- `orchestrator-app` can exchange tokens targeting `todo-app` and `notes-app`
- Uses OAuth2 token exchange grant type: `urn:ietf:params:oauth:grant-type:token-exchange`

### Client Roles

Hierarchical roles for fine-grained access control:
- **Realm roles**: Assigned at realm level
- **Client roles**: Scoped to specific clients
  - `orchestrator` (orchestrator-app)
  - `todo-admin`, `todo-user` (todo-app)
  - `notes-admin`, `notes-user` (notes-app)

### Service Account Roles

Service accounts are used when a client needs to act on its own behalf:
- `orchestrator-app` service account is assigned `todo-user` and `notes-user` roles

## Setup Steps

### Manual Setup in Keycloak Admin Console

1. **Create Scopes** (Realm > Client Scopes)
   - Add all scopes defined in `clients.yaml`

2. **Create Clients** (Realm > Clients)
   - Create `orchestrator-app` (Confidential, Authorization Code grant)
   - Create `todo-app` (Bearer only)
   - Create `notes-app` (Bearer only)

3. **Configure Protocol Mappers**
   - For each client, add mappers as defined in config
   - Ensure `username`, `email`, `groups` claims are mapped

4. **Enable Token Exchange**
   - For `orchestrator-app`: Realm > Token Exchange
   - Add permission: `orchestrator-app` can exchange for `todo-app` and `notes-app`

5. **Assign Client Roles**
   - Assign client roles to users or service accounts

### Important Notes

- Resource servers (`todo-app`, `notes-app`) must accept Bearer tokens with:
  - `preferred_username` claim for user identification
  - `groups` claim (array) for authorization
  - `audience` claim matching their client ID

- The orchestrator performs token exchange with grant type:
  ```
  urn:ietf:params:oauth:grant-type:token-exchange
  ```

- Exchanged tokens will have the `audience` claim set to the target resource server

## Token Flow

```
1. User logs in via orchestrator (password grant)
   → Receives access_token (audience: orchestrator-app)

2. Orchestrator exchanges token
   → POST to /token with token-exchange grant
   → Receives exchanged_token (audience: todo-app or notes-app)

3. Orchestrator sends exchanged_token to resource server
   → Authorization: Bearer <exchanged_token>
   → Resource server validates audience and extracts username
```

## Environment Variables

None required for this file; clients.yaml is a reference definition.

In production, use Keycloak Admin REST API or Keycloak Operator to automate client provisioning based on this YAML.
