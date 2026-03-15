const express = require('express');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const app = express();
app.use(express.json());

const port = process.env.PORT || 3001;
const groupsFile = path.join(__dirname, '..', 'config', 'groups.yaml');

function loadGroupsConfig(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed = yaml.load(raw);
  return parsed && parsed.groups ? parsed.groups : [];
}

const groups = loadGroupsConfig(groupsFile);

function groupExists(groupName) {
  return groups.some((g) => g.name === groupName);
}

function isUserInGroup(username, groupName) {
  const group = groups.find((g) => g.name === groupName);
  if (!group || !Array.isArray(group.members)) {
    return false;
  }

  return group.members.includes(username);
}

function canReadTodo(username) {
  return isUserInGroup(username, 'TODO_READ') || canWriteTodo(username)
}

function canWriteTodo(username) {
  return isUserInGroup(username, 'TODO_WRITE')
}

function projectGroupName(projectCode) {
  return `PROJECT_${String(projectCode || '').toUpperCase()}`;
}

function canAccessProject(username, projectCode) {
  return isUserInGroup(username, projectGroupName(projectCode));
}

let projects = [
  { id: 1, code: 'HR', name: 'HR Onboarding', description: 'Tasks for HR onboarding workflow' },
  { id: 2, code: 'FIN', name: 'Finance Cleanup', description: 'Tasks for monthly finance cleanup' }
];

let todos = [
  { id: 1, title: 'Create onboarding checklist', completed: false, projectId: 1 },
  { id: 2, title: 'Review payroll exports', completed: true, projectId: 2 }
];

function getUser(req) {
  return req.header('x-user') || req.query.user;
}

function requireUser(req, res, next) {
  const username = getUser(req);

  if (!username) {
    return res.status(401).json({ error: 'Missing user. Set x-user header or user query param.' });
  }

  req.username = username;
  return next();
}

function requireTodoRead(req, res, next) {
  if (!canReadTodo(req.username)) {
    return res.status(403).json({ error: `User ${req.username} cannot read TODO resources` });
  }

  return next();
}

function requireTodoWrite(req, res, next) {
  if (!canWriteTodo(req.username)) {
    return res.status(403).json({ error: `User ${req.username} cannot modify TODO resources` });
  }

  return next();
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'todo-app' });
});

app.get('/authz/:username', (req, res) => {
  const username = req.params.username;
  const userGroups = groups.filter((g) => Array.isArray(g.members) && g.members.includes(username)).map((g) => g.name);
  return res.json({ username, groups: userGroups });
});

app.get('/projects', requireUser, requireTodoRead, (req, res) => {
  const visibleProjects = projects.filter((p) => canAccessProject(req.username, p.code));
  res.json(visibleProjects);
});

app.post('/projects', requireUser, requireTodoWrite, (req, res) => {
  const { code, name, description = '' } = req.body;
  if (!code || !name) {
    return res.status(400).json({ error: 'code and name are required' });
  }

  const normalizedCode = String(code).toUpperCase();
  const groupName = projectGroupName(normalizedCode);

  if (!groupExists(groupName)) {
    return res.status(400).json({ error: `Unknown project group ${groupName} in groups.yaml` });
  }

  if (!canAccessProject(req.username, normalizedCode)) {
    return res.status(403).json({ error: `User ${req.username} is not a member of ${groupName}` });
  }

  if (projects.some((p) => p.code === normalizedCode)) {
    return res.status(409).json({ error: `Project with code ${normalizedCode} already exists` });
  }

  const nextId = projects.length ? Math.max(...projects.map((p) => p.id)) + 1 : 1;
  const project = { id: nextId, code: normalizedCode, name, description };
  projects.push(project);
  return res.status(201).json(project);
});

app.put('/projects/:id', requireUser, requireTodoWrite, (req, res) => {
  const id = Number(req.params.id);
  const idx = projects.findIndex((p) => p.id === id);
  if (idx === -1) {
    return res.status(404).json({ error: 'project not found' });
  }

  if (!canAccessProject(req.username, projects[idx].code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${projects[idx].code}` });
  }

  projects[idx] = {
    ...projects[idx],
    name: req.body.name ?? projects[idx].name,
    description: req.body.description ?? projects[idx].description
  };

  return res.json(projects[idx]);
});

app.delete('/projects/:id', requireUser, requireTodoWrite, (req, res) => {
  const id = Number(req.params.id);
  const project = projects.find((p) => p.id === id);
  if (!project) {
    return res.status(404).json({ error: 'project not found' });
  }

  if (!canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${project.code}` });
  }

  projects = projects.filter((p) => p.id !== id);
  todos = todos.filter((t) => t.projectId !== id);
  return res.status(204).send();
});

app.get('/todos', requireUser, requireTodoRead, (req, res) => {
  const projectId = req.query.projectId ? Number(req.query.projectId) : null;
  if (!projectId) {
    const visibleTodos = todos.filter((t) => {
      const project = projects.find((p) => p.id === t.projectId);
      return project && canAccessProject(req.username, project.code);
    });
    return res.json(visibleTodos);
  }

  const project = projects.find((p) => p.id === projectId);
  if (!project) {
    return res.status(404).json({ error: 'project not found' });
  }

  if (!canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${project.code}` });
  }

  return res.json(todos.filter((t) => t.projectId === projectId));
});

app.post('/todos', requireUser, requireTodoWrite, (req, res) => {
  const { title, completed = false, projectId } = req.body;
  if (!title || !projectId) {
    return res.status(400).json({ error: 'title and projectId are required' });
  }

  const project = projects.find((p) => p.id === Number(projectId));
  if (!project) {
    return res.status(400).json({ error: 'projectId does not exist' });
  }

  if (!canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${project.code}` });
  }

  const nextId = todos.length ? Math.max(...todos.map((t) => t.id)) + 1 : 1;
  const todo = { id: nextId, title, completed: Boolean(completed), projectId: Number(projectId) };
  todos.push(todo);
  return res.status(201).json(todo);
});

app.put('/todos/:id', requireUser, requireTodoWrite, (req, res) => {
  const id = Number(req.params.id);
  const idx = todos.findIndex((t) => t.id === id);
  if (idx === -1) {
    return res.status(404).json({ error: 'todo not found' });
  }

  const currentProject = projects.find((p) => p.id === todos[idx].projectId);
  if (!currentProject || !canAccessProject(req.username, currentProject.code)) {
    return res.status(403).json({ error: `User ${req.username} cannot modify this todo` });
  }

  if (req.body.projectId) {
    const targetProject = projects.find((p) => p.id === Number(req.body.projectId));
    if (!targetProject) {
      return res.status(400).json({ error: 'projectId does not exist' });
    }
    if (!canAccessProject(req.username, targetProject.code)) {
      return res.status(403).json({ error: `User ${req.username} is not assigned to project ${targetProject.code}` });
    }
  }

  todos[idx] = {
    ...todos[idx],
    title: req.body.title ?? todos[idx].title,
    completed: req.body.completed ?? todos[idx].completed,
    projectId: req.body.projectId ? Number(req.body.projectId) : todos[idx].projectId
  };

  return res.json(todos[idx]);
});

app.delete('/todos/:id', requireUser, requireTodoWrite, (req, res) => {
  const id = Number(req.params.id);
  const todo = todos.find((t) => t.id === id);
  if (!todo) {
    return res.status(404).json({ error: 'todo not found' });
  }

  const project = projects.find((p) => p.id === todo.projectId);
  if (!project || !canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} cannot delete this todo` });
  }

  todos = todos.filter((t) => t.id !== id);
  return res.status(204).send();
});

app.listen(port, () => {
  console.log(`todo-app listening on port ${port}`);
});
