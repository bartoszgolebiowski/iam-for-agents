This instruction tell you how to setup training instance for Keycloak.

1. Create a new Keycloak instance using the official Keycloak image from Docker Hub.

```bash
docker-compose -f resources/keycloack/docker-compose.yml up -d
```

2. Access the Keycloak admin console by navigating to `http://localhost:8080` in your web browser.

3. Log in using the default admin credentials:
   - Username: `admin`
   - Password: `admin`

## Bootstrap Users and Groups

This directory includes scripts and YAML configuration files to automatically create users and groups in Keycloak.

### Prerequisites

Before running the bootstrap scripts, ensure you have the following tools installed:

```bash
# On macOS
brew install curl yq jq

# On Ubuntu/Debian
sudo apt-get install curl jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# On Windows (with WSL)
sudo apt-get install curl jq yq
```

### Files

- **`users.yaml`** - Defines users to be created with their properties, credentials, and attributes
- **`groups.yaml`** - Defines groups and which users belong to them
- **`keycloak-admin-cli.sh`** - Helper script with functions to interact with Keycloak Admin REST API
- **`bootstrap-keycloak.sh`** - Main orchestration script that reads YAML files and creates users and groups

### Setup Steps

1. **Start Keycloak** (if not already running):
```bash
docker-compose -f resources/keycloack/docker-compose.yml up -d
```

2. **Make scripts executable**:
```bash
chmod +x resources/keycloack/bootstrap-keycloak.sh
chmod +x resources/keycloack/keycloak-admin-cli.sh
```

3. **Configure users** (optional):
   - Edit `users.yaml` to add/modify users
   - Edit `groups.yaml` to add/modify groups and their members

4. **Run bootstrap script**:

```bash
# Using default configuration
./resources/keycloack/bootstrap-keycloak.sh

# With custom Keycloak URL
./resources/keycloack/bootstrap-keycloak.sh -u http://keycloak.example.com:8080

# With custom credentials
./resources/keycloack/bootstrap-keycloak.sh -a admin_user -p admin_password

# With custom YAML files
./resources/keycloack/bootstrap-keycloak.sh --users-file /path/to/users.yaml --groups-file /path/to/groups.yaml
```

### Usage Examples

#### Example 1: Bootstrap with default settings
```bash
cd resources/keycloack
./bootstrap-keycloak.sh
```

#### Example 2: Bootstrap a specific realm
```bash
./bootstrap-keycloak.sh -r my-realm
```

#### Example 3: Bootstrap with all custom options
```bash
./bootstrap-keycloak.sh \
  -u http://localhost:8080 \
  -r master \
  -a admin \
  -p admin \
  --users-file users.yaml \
  --groups-file groups.yaml
```

### Configuration

#### users.yaml Structure

```yaml
users:
  - username: john_doe
    email: john@example.com
    firstName: John
    lastName: Doe
    enabled: true
    emailVerified: true
    credentials:
      - type: password
        value: secure_password_here
        temporary: false
    attributes:
      department: Engineering
      role: Developer
```

#### groups.yaml Structure

```yaml
groups:
  - name: developers
    description: Software developers group
    members:
      - john_doe
      - jane_smith
    attributes:
      department: Engineering
```

### Keycloak Admin CLI Functions

The `keycloak-admin-cli.sh` script provides the following functions:

- `get_access_token()` - Authenticate and get access token
- `create_user()` - Create a new user
- `get_user_id()` - Get user ID by username
- `create_group()` - Create a new group
- `get_group_id()` - Get group ID by name
- `add_user_to_group()` - Add user to group
- `set_user_attributes()` - Set user attributes

You can use these functions in your own scripts or automation tools.

### Troubleshooting

**Issue**: "curl: command not found"
- Solution: Install curl - `apt-get install curl` (Debian/Ubuntu) or `brew install curl` (macOS)

**Issue**: "jq: command not found"
- Solution: Install jq - `apt-get install jq` (Debian/Ubuntu) or `brew install jq` (macOS)

**Issue**: "yq: command not found"
- Solution: Install yq - See prerequisites section above

**Issue**: "Failed to obtain access token"
- Solution: Check that Keycloak is running and credentials are correct

**Issue**: "Keycloak is not accessible"
- Solution: Verify Keycloak URL and that the container is running (`docker ps`)

### API Reference

The scripts use Keycloak's Admin REST API. For more information:
- [Keycloak Admin REST API Documentation](https://www.keycloak.org/docs-api/latest/rest-api/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)