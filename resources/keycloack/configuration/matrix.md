# User-Group Membership Matrix

## Users to Groups Assignment

### TODO App Groups

| User | TODO_ADMIN | TODO_WRITE | TODO_READ |
|------|:----------:|:----------:|:---------:|
| alice | ❌ | ✅ | ✅ |
| bob | ❌ | ✅ | ❌ |
| charlie | ✅ | ❌ | ❌ |
| diana | ✅ | ❌ | ❌ |

### NOTES App Groups

| User | NOTES_ADMIN | NOTES_WRITE | NOTES_READ |
|------|:-----------:|:-----------:|:----------:|
| alice | ❌ | ✅ | ✅ |
| bob | ❌ | ✅ | ✅ |
| charlie | ✅ | ✅ | ❌ |
| diana | ✅ | ❌ | ❌ |

### Project Resource Groups

| User | PROJECT_HR | PROJECT_FIN | PROJECT_OPS | PROJECT_SALES |
|------|:----------:|:-----------:|:-----------:|:-------------:|
| alice | ✅ | ❌ | ❌ | ✅ |
| bob | ❌ | ✅ | ✅ | ❌ |
| charlie | ✅ | ✅ | ✅ | ❌ |
| diana | ✅ | ✅ | ❌ | ✅ |

## Groups to Users Assignment

| Group | Members | Count | Type | Description |
|-------|---------|-------|------|-------------|
| **TODO_ADMIN** | charlie, diana | 2 | Operation | TODO app administrators - full access |
| **TODO_WRITE** | alice, bob | 2 | Operation | TODO app writers - create and modify tasks |
| **TODO_READ** | alice | 1 | Operation | TODO app readers - view only access |
| **NOTES_ADMIN** | charlie, diana | 2 | Operation | NOTES app administrators - full access |
| **NOTES_WRITE** | alice, bob, charlie | 3 | Operation | NOTES app writers - create and modify notes |
| **NOTES_READ** | alice, bob | 2 | Operation | NOTES app readers - view only access |
| **PROJECT_HR** | alice, charlie, diana | 3 | Resource | HR Management project |
| **PROJECT_FIN** | bob, charlie, diana | 3 | Resource | Finance Management project |
| **PROJECT_OPS** | bob, charlie | 2 | Resource | Operations Management project |
| **PROJECT_SALES** | alice, diana | 2 | Resource | Sales Management project |

## User Summary

| User | Groups Count | Group List | Permissions |
|------|:------------:|------------|-------------|
| **alice** | 6 | TODO_WRITE, TODO_READ, NOTES_WRITE, NOTES_READ, PROJECT_HR, PROJECT_SALES | Write/Read for TODO & NOTES + 2 Projects |
| **bob** | 5 | TODO_WRITE, NOTES_WRITE, NOTES_READ, PROJECT_FIN, PROJECT_OPS | Write/Read for TODO & NOTES + 2 Projects |
| **charlie** | 6 | TODO_ADMIN, NOTES_ADMIN, NOTES_WRITE, PROJECT_HR, PROJECT_FIN, PROJECT_OPS | Admin for TODO & NOTES + 3 Projects |
| **diana** | 5 | TODO_ADMIN, NOTES_ADMIN, PROJECT_HR, PROJECT_FIN, PROJECT_SALES | Admin for TODO & NOTES + 3 Projects |

## Group Summary

### Operation Groups (Permission Levels)
- **TODO_ADMIN** - 2 members (charlie, diana) - Full administrative access to TODO app
- **TODO_WRITE** - 2 members (alice, bob) - Create and modify TODO tasks
- **TODO_READ** - 1 member (alice) - View only access to TODO app
- **NOTES_ADMIN** - 2 members (charlie, diana) - Full administrative access to NOTES app
- **NOTES_WRITE** - 3 members (alice, bob, charlie) - Create and modify notes
- **NOTES_READ** - 2 members (alice, bob) - View only access to NOTES app

### Resource Groups (Projects)
- **PROJECT_HR** - 3 members (alice, charlie, diana) - Human Resources Management
- **PROJECT_FIN** - 3 members (bob, charlie, diana) - Finance Management
- **PROJECT_OPS** - 2 members (bob, charlie) - Operations Management
- **PROJECT_SALES** - 2 members (alice, diana) - Sales Management

## Access Patterns

### Highest Privileges
- **charlie** & **diana**: Can perform admin operations on both TODO and NOTES apps across 3 projects

### Standard Access
- **alice**: Can write/read tasks, write/read notes, manage 2 projects (HR, Sales)
- **bob**: Can write/read tasks and notes, manage 2 projects (Finance, Operations)

### Multi-App Support
- All users have access to both TODO and NOTES apps with varying permission levels
- charlie has the broadest coverage with admin + write access across both apps
