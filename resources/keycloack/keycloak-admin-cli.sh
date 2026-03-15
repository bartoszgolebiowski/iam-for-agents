#!/bin/bash

# Keycloak Admin CLI Helper Functions
# Provides utilities for interacting with Keycloak Admin REST API

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-master}"
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

# Global variable to store access token
ACCESS_TOKEN=""

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get access token using admin credentials
get_access_token() {
    local response
    
    log_info "Authenticating with Keycloak..."
    
    response=$(curl -s -X POST \
        "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        -d "username=${KEYCLOAK_ADMIN_USER}" \
        -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
        2>/dev/null)
    
    ACCESS_TOKEN=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Failed to obtain access token. Check credentials and Keycloak availability."
        return 1
    fi
    
    log_info "Authentication successful"
    return 0
}

# Create a new user
# Usage: create_user <username> <email> <firstName> <lastName> <password> [enabled]
create_user() {
    local username="$1"
    local email="$2"
    local firstName="$3"
    local lastName="$4"
    local password="$5"
    local enabled="${6:-true}"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    # Check if user already exists
    local user_id
    user_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}" \
        2>/dev/null | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$user_id" ]; then
        log_warning "User '${username}' already exists (ID: ${user_id})"
        return 0
    fi
    
    log_info "Creating user '${username}'..."
    
    local user_json
    user_json=$(cat <<EOF
{
    "username": "${username}",
    "email": "${email}",
    "firstName": "${firstName}",
    "lastName": "${lastName}",
    "enabled": ${enabled},
    "emailVerified": true,
    "credentials": [
        {
            "type": "password",
            "value": "${password}",
            "temporary": false
        }
    ]
}
EOF
)
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$user_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users" \
        2>/dev/null)
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "201" ]; then
        log_info "User '${username}' created successfully"
        return 0
    else
        log_error "Failed to create user '${username}' (HTTP ${http_code})"
        echo "$response" | head -n-1
        return 1
    fi
}

# Get user ID by username
get_user_id() {
    local username="$1"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    local user_id
    user_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}" \
        2>/dev/null | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$user_id" ]; then
        echo "$user_id"
        return 0
    else
        log_error "User '${username}' not found"
        return 1
    fi
}

# Create a new group
# Usage: create_group <groupName> <description>
create_group() {
    local group_name="$1"
    local description="${2:-}"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    # Check if group already exists
    local group_id
    group_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/groups?search=${group_name}" \
        2>/dev/null | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$group_id" ]; then
        log_warning "Group '${group_name}' already exists (ID: ${group_id})"
        return 0
    fi
    
    log_info "Creating group '${group_name}'..."
    
    local group_json
    group_json=$(cat <<EOF
{
    "name": "${group_name}",
    "attributes": {
        "description": ["${description}"]
    }
}
EOF
)
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$group_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/groups" \
        2>/dev/null)
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "201" ]; then
        log_info "Group '${group_name}' created successfully"
        return 0
    else
        log_error "Failed to create group '${group_name}' (HTTP ${http_code})"
        echo "$response" | head -n-1
        return 1
    fi
}

# Get group ID by group name
get_group_id() {
    local group_name="$1"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    local group_id
    group_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/groups?search=${group_name}&exact=true" \
        2>/dev/null | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$group_id" ]; then
        echo "$group_id"
        return 0
    else
        log_error "Group '${group_name}' not found"
        return 1
    fi
}

# Add user to group
# Usage: add_user_to_group <username> <group_name>
add_user_to_group() {
    local username="$1"
    local group_name="$2"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    local user_id
    user_id=$(get_user_id "$username") || return 1
    
    local group_id
    group_id=$(get_group_id "$group_name") || return 1
    
    log_info "Adding user '${username}' to group '${group_name}'..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/groups/${group_id}" \
        2>/dev/null)
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "204" ]; then
        log_info "User '${username}' added to group '${group_name}' successfully"
        return 0
    else
        log_error "Failed to add user '${username}' to group '${group_name}' (HTTP ${http_code})"
        return 1
    fi
}

# Set user attributes
# Usage: set_user_attributes <username> <key1>:<value1> [<key2>:<value2> ...]
set_user_attributes() {
    local username="$1"
    shift
    local attributes=("$@")
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    local user_id
    user_id=$(get_user_id "$username") || return 1
    
    local attributes_json="{}"
    for attr in "${attributes[@]}"; do
        local key="${attr%%:*}"
        local value="${attr#*:}"
        attributes_json=$(echo "$attributes_json" | jq --arg k "$key" --arg v "$value" '.[$k] = [$v]')
    done
    
    log_info "Setting attributes for user '${username}'..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"attributes\": $attributes_json}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}" \
        2>/dev/null)
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "204" ]; then
        log_info "Attributes set for user '${username}' successfully"
        return 0
    else
        log_error "Failed to set attributes for user '${username}' (HTTP ${http_code})"
        return 1
    fi
}

# Create a client scope
# Usage: create_client_scope <name> <description> <protocol>
create_client_scope() {
    local name="$1"
    local description="$2"
    local protocol="${3:-openid-connect}"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    # Check if scope already exists
    local scope_id
    scope_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes" \
        2>/dev/null | jq -r ".[] | select(.name==\"$name\") | .id")
        
    if [ -n "$scope_id" ] && [ "$scope_id" != "null" ]; then
        log_warning "Client scope '${name}' already exists (ID: ${scope_id})"
        return 0
    fi
    
    log_info "Creating client scope '${name}'..."
    
    local scope_json
    scope_json=$(jq -a -cn \
        --arg name "$name" \
        --arg description "$description" \
        --arg protocol "$protocol" \
        '{
            name: $name,
            description: $description,
            protocol: $protocol
        }')
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$scope_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes" \
        2>/dev/null)
        
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "201" ]; then
        log_info "Client scope '${name}' created successfully"
        return 0
    else
        log_error "Failed to create client scope '${name}' (HTTP ${http_code})"
        return 1
    fi
}

# Create a client
# Usage: create_client <client_id> <secret> <description> <public> <standard_flow> <direct_access> <service_accounts> <redirect_uris_json> <web_origins_json> [protocol_mappers_json]
create_client() {
    local client_id="$1"
    local secret="$2"
    local description="$3"
    local public="${4:-false}"
    local standard_flow="${5:-true}"
    local direct_access="${6:-true}"
    local service_accounts="${7:-false}"
    local redirects="${8:-[]}"
    local web_origins="${9:-[]}"
    local protocol_mappers="${10:-[]}"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi
    
    # Check if client already exists
    local existing_id
    existing_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_id}" \
        2>/dev/null | jq -r '.[0].id')
        
    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        log_warning "Client '${client_id}' already exists"
        return 0
    fi
    
    log_info "Creating client '${client_id}'..."
    
    # Validate/normalize JSON array inputs to avoid malformed payloads.
    local redirects_json web_origins_json
    redirects_json=$(echo "$redirects" | jq -c 'if type == "array" then . else [] end' 2>/dev/null || echo "[]")
    web_origins_json=$(echo "$web_origins" | jq -c 'if type == "array" then . else [] end' 2>/dev/null || echo "[]")

    local protocol_mappers_json
    protocol_mappers_json=$(echo "$protocol_mappers" | jq -c 'if type == "array" then . else [] end' 2>/dev/null || echo "[]")

    local client_json
    client_json=$(jq -a -cn \
        --arg clientId "$client_id" \
        --arg secret "$secret" \
        --arg description "$description" \
        --argjson publicClient "$public" \
        --argjson standardFlowEnabled "$standard_flow" \
        --argjson directAccessGrantsEnabled "$direct_access" \
        --argjson serviceAccountsEnabled "$service_accounts" \
        --argjson redirectUris "$redirects_json" \
        --argjson webOrigins "$web_origins_json" \
        '{
            clientId: $clientId,
            secret: $secret,
            description: $description,
            publicClient: $publicClient,
            standardFlowEnabled: $standardFlowEnabled,
            directAccessGrantsEnabled: $directAccessGrantsEnabled,
            serviceAccountsEnabled: $serviceAccountsEnabled,
            clientAuthenticatorType: "client-secret",
            redirectUris: $redirectUris,
            webOrigins: $webOrigins
        }')

    # Add protocolMappers only if provided (omitting allows Keycloak to add defaults)
    if [ "$protocol_mappers_json" != "[]" ] && [ "$protocol_mappers_json" != "null" ]; then
        client_json=$(echo "$client_json" | jq --argjson pm "$protocol_mappers_json" '. + {protocolMappers: $pm}')
    fi
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$client_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
        2>/dev/null)
        
    local http_code
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "201" ]; then
        log_info "Client '${client_id}' created successfully"
        log_info "✓ Client Credentials:"
        log_info "  - Client ID: ${client_id}"
        log_info "  - Client Secret: ${secret}"
        return 0
    else
        local response_body
        response_body=$(echo "$response" | sed '$d')
        log_error "Failed to create client '${client_id}' (HTTP ${http_code})"
        [ -n "$response_body" ] && log_error "Response body: ${response_body}"
        log_error "Request payload: ${client_json}"
        return 1
    fi
}

# Get internal Keycloak client UUID by public clientId
get_client_internal_id() {
    local client_id="$1"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_id}" \
        2>/dev/null | jq -r '.[0].id // empty')

    if [ -n "$internal_id" ]; then
        echo "$internal_id"
        return 0
    fi

    log_error "Client '${client_id}' not found"
    return 1
}

# Create a client role
# Usage: create_client_role <client_id> <role_name> [description]
create_client_role() {
    local client_id="$1"
    local role_name="$2"
    local description="${3:-}"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(get_client_internal_id "$client_id") || return 1

    local exists_http_code
    exists_http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/roles/${role_name}" \
        2>/dev/null)

    if [ "$exists_http_code" == "200" ]; then
        log_warning "Role '${role_name}' already exists on client '${client_id}'"
        return 0
    fi

    log_info "Creating role '${role_name}' on client '${client_id}'..."

    local role_json
    role_json=$(jq -a -cn \
        --arg name "$role_name" \
        --arg description "$description" \
        '{name: $name, description: $description}')

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$role_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/roles" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "201" ] || [ "$http_code" == "204" ]; then
        log_info "Role '${role_name}' created on client '${client_id}'"
        return 0
    fi

    local response_body
    response_body=$(echo "$response" | sed '$d')
    log_error "Failed to create role '${role_name}' on client '${client_id}' (HTTP ${http_code})"
    [ -n "$response_body" ] && log_error "Response body: ${response_body}"
    return 1
}

# Get service account user ID for a client with service accounts enabled
# Usage: get_service_account_user_id <client_id>
get_service_account_user_id() {
    local client_id="$1"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(get_client_internal_id "$client_id") || return 1

    local user_id
    user_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/service-account-user" \
        2>/dev/null | jq -r '.id // empty')

    if [ -n "$user_id" ]; then
        echo "$user_id"
        return 0
    fi

    log_error "Service account user not found for client '${client_id}'"
    return 1
}

# Assign a realm role to a user by user ID
# Usage: assign_realm_role_to_user_id <user_id> <realm_role_name>
assign_realm_role_to_user_id() {
    local user_id="$1"
    local role_name="$2"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local role_json
    role_json=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/roles/${role_name}" \
        2>/dev/null)

    if [ -z "$role_json" ] || [ "$(echo "$role_json" | jq -r '.error // empty' 2>/dev/null)" != "" ]; then
        log_error "Realm role '${role_name}' not found"
        return 1
    fi

    local payload
    payload=$(jq -a -cn --argjson role "$role_json" '[ $role ]')

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/realm" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "204" ]; then
        log_info "Assigned realm role '${role_name}' to user '${user_id}'"
        return 0
    fi

    local response_body
    response_body=$(echo "$response" | sed '$d')
    log_error "Failed to assign realm role '${role_name}' to user '${user_id}' (HTTP ${http_code})"
    [ -n "$response_body" ] && log_error "Response body: ${response_body}"
    return 1
}

# Assign a client role to a user by user ID
# Usage: assign_client_role_to_user_id <user_id> <target_client_id> <role_name>
assign_client_role_to_user_id() {
    local user_id="$1"
    local target_client_id="$2"
    local role_name="$3"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local target_internal_id
    target_internal_id=$(get_client_internal_id "$target_client_id") || return 1

    local role_json
    role_json=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${target_internal_id}/roles/${role_name}" \
        2>/dev/null)

    if [ -z "$role_json" ] || [ "$(echo "$role_json" | jq -r '.error // empty' 2>/dev/null)" != "" ]; then
        log_error "Role '${role_name}' not found on client '${target_client_id}'"
        return 1
    fi

    local payload
    payload=$(jq -a -cn --argjson role "$role_json" '[ $role ]')

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/clients/${target_internal_id}" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "204" ]; then
        log_info "Assigned client role '${role_name}' (${target_client_id}) to user '${user_id}'"
        return 0
    fi

    local response_body
    response_body=$(echo "$response" | sed '$d')
    log_error "Failed to assign client role '${role_name}' (${target_client_id}) to user '${user_id}' (HTTP ${http_code})"
    [ -n "$response_body" ] && log_error "Response body: ${response_body}"
    return 1
}

# Assign a client role to a group
# Usage: assign_client_role_to_group <group_name> <target_client_id> <role_name>
assign_client_role_to_group() {
    local group_name="$1"
    local target_client_id="$2"
    local role_name="$3"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local group_id
    group_id=$(get_group_id "$group_name") || return 1

    local target_internal_id
    target_internal_id=$(get_client_internal_id "$target_client_id") || return 1

    local role_json
    role_json=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${target_internal_id}/roles/${role_name}" \
        2>/dev/null)

    if [ -z "$role_json" ] || [ "$(echo "$role_json" | jq -r '.error // empty' 2>/dev/null)" != "" ]; then
        log_error "Role '${role_name}' not found on client '${target_client_id}'"
        return 1
    fi

    local payload
    payload=$(jq -a -cn --argjson role "$role_json" '[ $role ]')

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/groups/${group_id}/role-mappings/clients/${target_internal_id}" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "204" ]; then
        log_info "Assigned client role '${role_name}' (${target_client_id}) to group '${group_name}'"
        return 0
    fi

    local response_body
    response_body=$(echo "$response" | sed '$d')
    log_error "Failed to assign client role '${role_name}' (${target_client_id}) to group '${group_name}' (HTTP ${http_code})"
    [ -n "$response_body" ] && log_error "Response body: ${response_body}"
    return 1
}

# Get client scope internal ID by name
# Usage: get_client_scope_id <scope_name>
get_client_scope_id() {
    local scope_name="$1"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local scope_id
    scope_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/client-scopes" \
        2>/dev/null | jq -r ".[] | select(.name==\"$scope_name\") | .id // empty")

    if [ -n "$scope_id" ]; then
        echo "$scope_id"
        return 0
    fi

    log_error "Client scope '${scope_name}' not found"
    return 1
}

# Assign a default client scope to a client
# Usage: assign_default_client_scope <client_id> <scope_name>
assign_default_client_scope() {
    local client_id="$1"
    local scope_name="$2"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(get_client_internal_id "$client_id") || return 1

    local scope_id
    scope_id=$(get_client_scope_id "$scope_name") || return 1

    log_info "Assigning default scope '${scope_name}' to client '${client_id}'..."

    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/default-client-scopes/${scope_id}" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "204" ]; then
        log_info "Default scope '${scope_name}' assigned to client '${client_id}'"
        return 0
    fi

    log_error "Failed to assign default scope '${scope_name}' to '${client_id}' (HTTP ${http_code})"
    return 1
}

# Assign an optional client scope to a client
# Usage: assign_optional_client_scope <client_id> <scope_name>
assign_optional_client_scope() {
    local client_id="$1"
    local scope_name="$2"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(get_client_internal_id "$client_id") || return 1

    local scope_id
    scope_id=$(get_client_scope_id "$scope_name") || return 1

    log_info "Assigning optional scope '${scope_name}' to client '${client_id}'..."

    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/optional-client-scopes/${scope_id}" \
        2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" == "204" ]; then
        log_info "Optional scope '${scope_name}' assigned to client '${client_id}'"
        return 0
    fi

    log_error "Failed to assign optional scope '${scope_name}' to '${client_id}' (HTTP ${http_code})"
    return 1
}

# Enable management permissions on a client (required for token exchange)
# Usage: enable_client_management_permissions <client_id>
enable_client_management_permissions() {
    local client_id="$1"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    local internal_id
    internal_id=$(get_client_internal_id "$client_id") || return 1

    log_info "Enabling management permissions on client '${client_id}'..."

    local response
    response=$(curl -s -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"enabled": true}' \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}/management/permissions" \
        2>/dev/null)

    local enabled
    enabled=$(echo "$response" | jq -r '.enabled // empty' 2>/dev/null)

    if [ "$enabled" == "true" ]; then
        log_info "Management permissions enabled on client '${client_id}'"
        echo "$response"
        return 0
    fi

    log_error "Failed to enable management permissions on client '${client_id}'"
    log_error "Response: ${response}"
    return 1
}

# Setup token exchange permission: create client policy and assign to token-exchange permission
# Usage: setup_token_exchange_permission <target_client_id> <source_client_id> [policy_name]
setup_token_exchange_permission() {
    local target_client_id="$1"
    local source_client_id="$2"
    local policy_name="${3:-allow-token-exchange}"

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Not authenticated. Call get_access_token first."
        return 1
    fi

    # 1. Enable management permissions on the target client and get token-exchange permission ID
    local perm_response
    perm_response=$(enable_client_management_permissions "$target_client_id") || return 1

    local token_exchange_perm_id
    token_exchange_perm_id=$(echo "$perm_response" | jq -r '.scopePermissions["token-exchange"] // empty' 2>/dev/null)

    if [ -z "$token_exchange_perm_id" ]; then
        log_error "token-exchange permission not found for client '${target_client_id}'"
        return 1
    fi

    log_info "Token exchange permission ID: ${token_exchange_perm_id}"

    # 2. Get the realm-management client internal ID
    local rm_internal_id
    rm_internal_id=$(get_client_internal_id "realm-management") || return 1

    # 3. Get the source client's internal ID
    local source_internal_id
    source_internal_id=$(get_client_internal_id "$source_client_id") || return 1

    # 4. Create a client policy in realm-management's authorization
    log_info "Creating client policy '${policy_name}' for token exchange..."

    local policy_json
    policy_json=$(jq -a -cn \
        --arg name "$policy_name" \
        --arg clientId "$source_internal_id" \
        '{
            type: "client",
            name: $name,
            logic: "POSITIVE",
            decisionStrategy: "UNANIMOUS",
            clients: [$clientId]
        }')

    local policy_response
    policy_response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$policy_json" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${rm_internal_id}/authz/resource-server/policy/client" \
        2>/dev/null)

    local policy_http_code
    policy_http_code=$(echo "$policy_response" | tail -n1)
    local policy_body
    policy_body=$(echo "$policy_response" | sed '$d')

    local policy_id
    if [ "$policy_http_code" == "201" ]; then
        policy_id=$(echo "$policy_body" | jq -r '.id // empty')
        log_info "Policy '${policy_name}' created (ID: ${policy_id})"
    elif [ "$policy_http_code" == "409" ]; then
        # Policy already exists, look it up
        log_warning "Policy '${policy_name}' already exists, looking up..."
        policy_id=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${rm_internal_id}/authz/resource-server/policy?name=${policy_name}" \
            2>/dev/null | jq -r '.[0].id // empty')

        if [ -z "$policy_id" ]; then
            log_error "Could not find existing policy '${policy_name}'"
            return 1
        fi
        log_info "Found existing policy '${policy_name}' (ID: ${policy_id})"
    else
        log_error "Failed to create policy '${policy_name}' (HTTP ${policy_http_code})"
        [ -n "$policy_body" ] && log_error "Response: ${policy_body}"
        return 1
    fi

    # 5. Get the current token-exchange permission and attach the policy
    log_info "Assigning policy to token-exchange permission..."

    local perm_detail
    perm_detail=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${rm_internal_id}/authz/resource-server/permission/scope/${token_exchange_perm_id}" \
        2>/dev/null)

    local updated_perm
    updated_perm=$(echo "$perm_detail" | jq --arg pid "$policy_id" \
        '.policies = ((.policies // []) + [$pid] | unique)')

    local update_response
    update_response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$updated_perm" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${rm_internal_id}/authz/resource-server/permission/scope/${token_exchange_perm_id}" \
        2>/dev/null)

    local update_http_code
    update_http_code=$(echo "$update_response" | tail -n1)

    if [ "$update_http_code" == "201" ] || [ "$update_http_code" == "200" ] || [ "$update_http_code" == "204" ]; then
        log_info "Token exchange permission configured: ${source_client_id} -> ${target_client_id}"
        return 0
    fi

    local update_body
    update_body=$(echo "$update_response" | sed '$d')
    log_error "Failed to update token-exchange permission (HTTP ${update_http_code})"
    [ -n "$update_body" ] && log_error "Response: ${update_body}"
    return 1
}