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
# Usage: create_client <client_id> <secret> <description> <public> <standard_flow> <direct_access> <service_accounts> <redirect_uris_json> <web_origins_json>
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