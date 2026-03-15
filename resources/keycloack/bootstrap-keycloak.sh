#!/bin/bash

# Bootstrap Keycloak Users, Groups, and Clients
# Usage: ./bootstrap-keycloak.sh [options]
# Options:
#   -u, --url URL           Keycloak URL (default: http://localhost:8080)
#   -r, --realm REALM       Realm name (default: master)
#   -a, --admin USER        Admin username (default: admin)
#   -p, --password PASS     Admin password (default: admin)
#   --users-file FILE       Path to users YAML file (default: users.yaml)
#   --groups-file FILE      Path to groups YAML file (default: groups.yaml)
#   --clients-file FILE     Path to clients YAML file (default: clients.yaml)
#   -h, --help             Show this help message

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
KEYCLOAK_URL="http://localhost:8080"
KEYCLOAK_REALM="master"
KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASSWORD="admin"
USERS_FILE="${SCRIPT_DIR}/configuration/users.yaml"
GROUPS_FILE="${SCRIPT_DIR}/configuration/groups.yaml"
CLIENTS_FILE="${SCRIPT_DIR}/configuration/clients.yaml"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            KEYCLOAK_URL="$2"
            shift 2
            ;;
        -r|--realm)
            KEYCLOAK_REALM="$2"
            shift 2
            ;;
        -a|--admin)
            KEYCLOAK_ADMIN_USER="$2"
            shift 2
            ;;
        -p|--password)
            KEYCLOAK_ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --users-file)
            USERS_FILE="$2"
            shift 2
            ;;
        --groups-file)
            GROUPS_FILE="$2"
            shift 2
            ;;
        --clients-file)
            CLIENTS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

show_help() {
    cat <<EOF
Bootstrap Keycloak Users, Groups, and Clients

Usage: $0 [options]

Options:
  -u, --url URL           Keycloak URL (default: http://localhost:8080)
  -r, --realm REALM       Realm name (default: master)
  -a, --admin USER        Admin username (default: admin)
  -p, --password PASS     Admin password (default: admin)
  --users-file FILE       Path to users YAML file (default: users.yaml)
  --groups-file FILE      Path to groups YAML file (default: groups.yaml)
  --clients-file FILE     Path to clients YAML file (default: clients.yaml)
  -h, --help             Show this help message

Examples:
  # Bootstrap with default values
  $0

  # Bootstrap with custom YAML files
  $0 --users-file /etc/keycloak/users.yaml --groups-file /etc/keycloak/groups.yaml --clients-file /etc/keycloak/clients.yaml
EOF
}

# Source the admin CLI functions
if [ ! -f "${SCRIPT_DIR}/keycloak-admin-cli.sh" ]; then
    echo "[ERROR] keycloak-admin-cli.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

source "${SCRIPT_DIR}/keycloak-admin-cli.sh"

# Override environment variables with command line arguments
export KEYCLOAK_URL
export KEYCLOAK_REALM
export KEYCLOAK_ADMIN_USER
export KEYCLOAK_ADMIN_PASSWORD

# Check prerequisites
check_prerequisites() {
    local tools=("curl" "yq" "jq")
    local missing=0
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Please install missing tools and try again."
        exit 1
    fi
}

# Parse users from YAML and create them
bootstrap_users() {
    if [ ! -f "$USERS_FILE" ]; then
        log_error "Users file not found: $USERS_FILE"
        return 1
    fi
    
    log_info "Starting to bootstrap users from $USERS_FILE..."
    
    # Use yq to extract and process each user
    local user_count
    user_count=$(yq '.users | length' "$USERS_FILE")
    
    log_info "Found $user_count users to create"
    
    for ((i=0; i<user_count; i++)); do
        local username email firstName lastName password enabled
        
        username=$(yq ".users[$i].username" "$USERS_FILE")
        email=$(yq ".users[$i].email" "$USERS_FILE")
        firstName=$(yq ".users[$i].firstName" "$USERS_FILE")
        lastName=$(yq ".users[$i].lastName" "$USERS_FILE")
        password=$(yq ".users[$i].credentials[0].value" "$USERS_FILE")
        enabled=$(yq ".users[$i].enabled" "$USERS_FILE")
        
        create_user "$username" "$email" "$firstName" "$lastName" "$password" "$enabled"
        
        # Set user attributes if they exist
        local attr_count
        attr_count=$(yq ".users[$i].attributes | length" "$USERS_FILE" 2>/dev/null || echo 0)
        
        if [ "$attr_count" -gt 0 ]; then
            local attrs=()
            for ((j=0; j<attr_count; j++)); do
                local key value
                key=$(yq ".users[$i].attributes | keys[$j]" "$USERS_FILE")
                value=$(yq ".users[$i].attributes[$key]" "$USERS_FILE")
                attrs+=("$key:$value")
            done
            
            if [ ${#attrs[@]} -gt 0 ]; then
                set_user_attributes "$username" "${attrs[@]}" || true
            fi
        fi
    done
    
    log_info "User bootstrap completed"
}

# Parse groups from YAML and create them
bootstrap_groups() {
    if [ ! -f "$GROUPS_FILE" ]; then
        log_error "Groups file not found: $GROUPS_FILE"
        return 1
    fi
    
    log_info "Starting to bootstrap groups from $GROUPS_FILE..."
    
    # Use yq to extract and process each group
    local group_count
    group_count=$(yq '.groups | length' "$GROUPS_FILE")
    
    log_info "Found $group_count groups to create"
    
    for ((i=0; i<group_count; i++)); do
        local group_name description
        
        group_name=$(yq ".groups[$i].name" "$GROUPS_FILE")
        description=$(yq ".groups[$i].description" "$GROUPS_FILE" 2>/dev/null || echo "")
        
        create_group "$group_name" "$description"
        
        # Add members to group
        local member_count
        member_count=$(yq ".groups[$i].members | length" "$GROUPS_FILE" 2>/dev/null || echo 0)
        
        if [ "$member_count" -gt 0 ]; then
            for ((j=0; j<member_count; j++)); do
                local member_name
                member_name=$(yq ".groups[$i].members[$j]" "$GROUPS_FILE")
                add_user_to_group "$member_name" "$group_name" || true
            done
        fi
    done
    
    log_info "Group bootstrap completed"
}

# Parse clients and scopes from YAML and create them
bootstrap_clients() {
    if [ ! -f "$CLIENTS_FILE" ]; then
        log_error "Clients file not found: $CLIENTS_FILE"
        return 1
    fi
    
    log_info "Starting to bootstrap clients and scopes from $CLIENTS_FILE..."
    
    # 1. Create Client Scopes
    local scope_count
    scope_count=$(yq '.scopes | length' "$CLIENTS_FILE" 2>/dev/null || echo 0)
    
    if [ "$scope_count" -gt 0 ] && [ "$scope_count" != "null" ]; then
        log_info "Found $scope_count custom scopes to create"
        for ((i=0; i<scope_count; i++)); do
            local scope_id scope_desc scope_proto
            scope_id=$(yq ".scopes[$i].id" "$CLIENTS_FILE")
            scope_desc=$(yq ".scopes[$i].description" "$CLIENTS_FILE")
            scope_proto=$(yq ".scopes[$i].protocol" "$CLIENTS_FILE")
            
            create_client_scope "$scope_id" "$scope_desc" "$scope_proto"
        done
    else
        log_info "No custom scopes found in $CLIENTS_FILE"
    fi

    # 2. Create Clients
    local client_keys
    client_keys=$(yq '.clients | keys | .[]' "$CLIENTS_FILE" 2>/dev/null || echo "")
    
    if [ -n "$client_keys" ]; then
        log_info "Creating clients..."
        for key in $client_keys; do
            local c_id c_secret c_desc c_pub c_std c_dir c_svc c_redirects c_web_origins
            
            c_id=$(yq -r ".clients[\"$key\"].clientId" "$CLIENTS_FILE")
            c_secret=$(yq -r ".clients[\"$key\"].clientSecret" "$CLIENTS_FILE")
            c_desc=$(yq -r ".clients[\"$key\"].description // \"\"" "$CLIENTS_FILE" 2>/dev/null || echo "")
            c_pub=$(yq -r ".clients[\"$key\"].public" "$CLIENTS_FILE")
            c_std=$(yq -r ".clients[\"$key\"].standardFlowEnabled" "$CLIENTS_FILE")
            c_dir=$(yq -r ".clients[\"$key\"].directAccessGrantsEnabled" "$CLIENTS_FILE")
            c_svc=$(yq -r ".clients[\"$key\"].serviceAccountsEnabled" "$CLIENTS_FILE")
            c_redirects=$(yq -o=json -I=0 ".clients[\"$key\"].redirectUris // []" "$CLIENTS_FILE" 2>/dev/null || echo "[]")
            c_web_origins=$(yq -o=json -I=0 ".clients[\"$key\"].webOrigins // []" "$CLIENTS_FILE" 2>/dev/null || echo "[]")
            c_mappers=$(yq -o=json -I=0 ".clients[\"$key\"].protocolMappers // []" "$CLIENTS_FILE" 2>/dev/null || echo "[]")
            
            # Handle nulls gracefully if fields are missing
            [ "$c_pub" == "null" ] && c_pub="false"
            [ "$c_std" == "null" ] && c_std="false"
            [ "$c_dir" == "null" ] && c_dir="false"
            [ "$c_svc" == "null" ] && c_svc="false"
            
            create_client "$c_id" "$c_secret" "$c_desc" "$c_pub" "$c_std" "$c_dir" "$c_svc" "$c_redirects" "$c_web_origins" "$c_mappers"
        done
    else
        log_info "No clients found in $CLIENTS_FILE"
    fi
    
    log_info "Client and scope bootstrap completed"
}

# Parse client roles and service account role mappings from YAML
bootstrap_client_role_mappings() {
    if [ ! -f "$CLIENTS_FILE" ]; then
        log_error "Clients file not found: $CLIENTS_FILE"
        return 1
    fi

    log_info "Starting to bootstrap client roles and service-account mappings from $CLIENTS_FILE..."

    # 1. Create declared client roles
    local role_client_keys
    role_client_keys=$(yq '.clientRoles | keys | .[]' "$CLIENTS_FILE" 2>/dev/null || echo "")

    if [ -n "$role_client_keys" ]; then
        for client_key in $role_client_keys; do
            local role_count
            role_count=$(yq ".clientRoles[\"$client_key\"] | length" "$CLIENTS_FILE" 2>/dev/null || echo 0)

            if [ "$role_count" == "null" ] || [ "$role_count" -le 0 ]; then
                continue
            fi

            for ((i=0; i<role_count; i++)); do
                local role_name role_desc
                role_name=$(yq -r ".clientRoles[\"$client_key\"][$i].name" "$CLIENTS_FILE")
                role_desc=$(yq -r ".clientRoles[\"$client_key\"][$i].description // \"\"" "$CLIENTS_FILE" 2>/dev/null || echo "")

                [ -z "$role_name" ] || [ "$role_name" == "null" ] && continue
                create_client_role "$client_key" "$role_name" "$role_desc"
            done
        done
    else
        log_info "No clientRoles section found in $CLIENTS_FILE"
    fi

    # 2. Assign client roles to groups (group-based authorization model)
    if [ ! -f "$GROUPS_FILE" ]; then
        log_warning "Groups file not found: $GROUPS_FILE (skipping group role mappings)"
        log_info "Client role bootstrap completed"
        return 0
    fi

    local group_count
    group_count=$(yq '.groups | length' "$GROUPS_FILE" 2>/dev/null || echo 0)

    if [ "$group_count" == "null" ] || [ "$group_count" -le 0 ]; then
        log_info "No groups found in $GROUPS_FILE; skipping group role mappings"
        log_info "Client role bootstrap completed"
        return 0
    fi

    for ((g=0; g<group_count; g++)); do
        local group_name
        group_name=$(yq -r ".groups[$g].name" "$GROUPS_FILE")

        [ -z "$group_name" ] || [ "$group_name" == "null" ] && continue

        local cr_count
        cr_count=$(yq ".groups[$g].clientRoles | length" "$GROUPS_FILE" 2>/dev/null || echo 0)
        [ "$cr_count" == "null" ] && cr_count=0

        if [ "$cr_count" -le 0 ]; then
            log_warning "No clientRoles mapping defined for group '${group_name}', skipping"
            continue
        fi

        for ((r=0; r<cr_count; r++)); do
            local cr_client cr_role
            cr_client=$(yq -r ".groups[$g].clientRoles[$r].client" "$GROUPS_FILE")
            cr_role=$(yq -r ".groups[$g].clientRoles[$r].role" "$GROUPS_FILE")

            [ -z "$cr_client" ] || [ "$cr_client" == "null" ] && continue
            [ -z "$cr_role" ]   || [ "$cr_role"   == "null" ] && continue

            assign_client_role_to_group "$group_name" "$cr_client" "$cr_role"
        done
    done

    log_info "Client role and group mapping bootstrap completed"
}

# Assign default and optional client scopes to clients
bootstrap_client_scope_assignments() {
    if [ ! -f "$CLIENTS_FILE" ]; then
        log_error "Clients file not found: $CLIENTS_FILE"
        return 1
    fi

    log_info "Starting to assign client scopes from $CLIENTS_FILE..."

    local client_keys
    client_keys=$(yq '.clients | keys | .[]' "$CLIENTS_FILE" 2>/dev/null || echo "")

    if [ -z "$client_keys" ]; then
        log_info "No clients found in $CLIENTS_FILE"
        return 0
    fi

    for key in $client_keys; do
        local c_id
        c_id=$(yq -r ".clients[\"$key\"].clientId" "$CLIENTS_FILE")

        # Assign default scopes
        local default_count
        default_count=$(yq ".clients[\"$key\"].defaultClientScopes | length" "$CLIENTS_FILE" 2>/dev/null || echo 0)
        [ "$default_count" == "null" ] && default_count=0

        for ((i=0; i<default_count; i++)); do
            local scope_name
            scope_name=$(yq -r ".clients[\"$key\"].defaultClientScopes[$i]" "$CLIENTS_FILE")
            assign_default_client_scope "$c_id" "$scope_name" || true
        done

        # Assign optional scopes
        local optional_count
        optional_count=$(yq ".clients[\"$key\"].optionalClientScopes | length" "$CLIENTS_FILE" 2>/dev/null || echo 0)
        [ "$optional_count" == "null" ] && optional_count=0

        for ((i=0; i<optional_count; i++)); do
            local scope_name
            scope_name=$(yq -r ".clients[\"$key\"].optionalClientScopes[$i]" "$CLIENTS_FILE")
            assign_optional_client_scope "$c_id" "$scope_name" || true
        done
    done

    log_info "Client scope assignment completed"
}

# Configure token exchange permissions from YAML
bootstrap_token_exchange() {
    if [ ! -f "$CLIENTS_FILE" ]; then
        log_error "Clients file not found: $CLIENTS_FILE"
        return 1
    fi

    local source_client
    source_client=$(yq -r '.tokenExchange.sourceClient // empty' "$CLIENTS_FILE" 2>/dev/null)

    if [ -z "$source_client" ]; then
        log_info "No tokenExchange section found in $CLIENTS_FILE"
        return 0
    fi

    log_info "Starting to configure token exchange permissions..."
    log_info "Source client: ${source_client}"

    local target_count
    target_count=$(yq '.tokenExchange.targetClients | length' "$CLIENTS_FILE" 2>/dev/null || echo 0)

    for ((i=0; i<target_count; i++)); do
        local target_id policy_name
        target_id=$(yq -r ".tokenExchange.targetClients[$i].clientId" "$CLIENTS_FILE")
        policy_name=$(yq -r ".tokenExchange.targetClients[$i].policy.name" "$CLIENTS_FILE")

        [ -z "$target_id" ] || [ "$target_id" == "null" ] && continue

        setup_token_exchange_permission "$target_id" "$source_client" "$policy_name" || true
    done

    log_info "Token exchange configuration completed"
}

# Assign roles to service accounts
bootstrap_service_account_roles() {
    if [ ! -f "$CLIENTS_FILE" ]; then
        log_error "Clients file not found: $CLIENTS_FILE"
        return 1
    fi

    log_info "Starting to assign service account roles from $CLIENTS_FILE..."

    local sa_client_keys
    sa_client_keys=$(yq '.serviceAccountRoles | keys | .[]' "$CLIENTS_FILE" 2>/dev/null || echo "")

    if [ -z "$sa_client_keys" ]; then
        log_info "No serviceAccountRoles section found in $CLIENTS_FILE"
        return 0
    fi

    for client_key in $sa_client_keys; do
        log_info "Processing service account for client '${client_key}'..."

        local sa_user_id
        sa_user_id=$(get_service_account_user_id "$client_key") || {
            log_error "Could not get service account for '${client_key}'"
            continue
        }

        # Assign realm roles
        local realm_role_count
        realm_role_count=$(yq ".serviceAccountRoles[\"$client_key\"].realmRoles | length" "$CLIENTS_FILE" 2>/dev/null || echo 0)
        [ "$realm_role_count" == "null" ] && realm_role_count=0

        for ((i=0; i<realm_role_count; i++)); do
            local role_name
            role_name=$(yq -r ".serviceAccountRoles[\"$client_key\"].realmRoles[$i]" "$CLIENTS_FILE")
            assign_realm_role_to_user_id "$sa_user_id" "$role_name" || true
        done

        # Assign client roles
        local client_role_count
        client_role_count=$(yq ".serviceAccountRoles[\"$client_key\"].clientRoles | length" "$CLIENTS_FILE" 2>/dev/null || echo 0)
        [ "$client_role_count" == "null" ] && client_role_count=0

        for ((i=0; i<client_role_count; i++)); do
            local target_client role_name
            target_client=$(yq -r ".serviceAccountRoles[\"$client_key\"].clientRoles[$i].client" "$CLIENTS_FILE")
            role_name=$(yq -r ".serviceAccountRoles[\"$client_key\"].clientRoles[$i].role" "$CLIENTS_FILE")

            assign_client_role_to_user_id "$sa_user_id" "$target_client" "$role_name" || true
        done
    done

    log_info "Service account role assignment completed"
}

# Main execution
main() {
    echo ""
    log_info "=========================================="
    log_info "Keycloak Bootstrap Script"
    log_info "=========================================="
    echo ""
    
    log_info "Configuration:"
    log_info "  Keycloak URL: $KEYCLOAK_URL"
    log_info "  Realm: $KEYCLOAK_REALM"
    log_info "  Admin User: $KEYCLOAK_ADMIN_USER"
    log_info "  Users file: $USERS_FILE"
    log_info "  Groups file: $GROUPS_FILE"
    log_info "  Clients file: $CLIENTS_FILE"
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_prerequisites
    
    # Authenticate
    if ! get_access_token; then
        log_error "Authentication failed"
        exit 1
    fi
    
    # Bootstrap clients & scopes
    if ! bootstrap_clients; then
        log_error "Client bootstrap failed"
        exit 1
    fi

    echo ""

    # Assign default and optional scopes to clients
    if ! bootstrap_client_scope_assignments; then
        log_error "Client scope assignment failed"
        exit 1
    fi

    echo ""

    # Bootstrap users
    if ! bootstrap_users; then
        log_error "User bootstrap failed"
        exit 1
    fi
    
    echo ""
    
    # Bootstrap groups
    if ! bootstrap_groups; then
        log_error "Group bootstrap failed"
        exit 1
    fi

    echo ""

    # Bootstrap client-role mappings after groups are created
    if ! bootstrap_client_role_mappings; then
        log_error "Client role bootstrap failed"
        exit 1
    fi

    echo ""

    # Configure token exchange permissions
    if ! bootstrap_token_exchange; then
        log_error "Token exchange configuration failed"
        exit 1
    fi

    echo ""

    # Assign roles to service accounts
    if ! bootstrap_service_account_roles; then
        log_error "Service account role assignment failed"
        exit 1
    fi
    
    echo ""
    log_info "=========================================="
    log_info "Bootstrap completed successfully!"
    log_info "=========================================="
    echo ""
    
    # Print summary
    log_info "Access Keycloak: $KEYCLOAK_URL"
    log_info "Admin Console: $KEYCLOAK_URL/admin"
    log_info "Credentials: $KEYCLOAK_ADMIN_USER / *****"
}

# Run main function
main "$@"