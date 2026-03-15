const express = require('express');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const app = express();
app.use(express.json());

const port = process.env.PORT || 3002;
const groupsFile = process.env.GROUPS_FILE || path.join(__dirname, '..', 'config', 'groups.yaml');

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

function canReadNotes(username) {
  return isUserInGroup(username, 'NOTES_READ') || canWriteNotes(username);
}

function canWriteNotes(username) {
  return isUserInGroup(username, 'NOTES_WRITE')
}

function projectGroupName(projectCode) {
  return `PROJECT_${String(projectCode || '').toUpperCase()}`;
}

function canAccessProject(username, projectCode) {
  return isUserInGroup(username, projectGroupName(projectCode));
}

let projects = [
  { id: 1, code: 'HR', name: 'Knowledge Base', description: 'Team knowledge notes' },
  { id: 2, code: 'FIN', name: 'Meeting Notes', description: 'Recurring meeting notes by topic' }
];

let notes = [
  { id: 1, title: 'Keycloak setup', content: 'Use docker compose under resources/keycloack', projectId: 1 },
  { id: 2, title: 'Sprint retro', content: 'Capture action items and owners', projectId: 2 }
];

function getUser(req) {
  const directUser = req.header('x-user') || req.query.user;
  if (directUser) {
    return directUser;
  }

  const authHeader = req.header('authorization') || '';
  if (!authHeader.startsWith('Bearer ')) {
    return null;
  }

  const token = authHeader.slice('Bearer '.length).trim();
  const parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }

  try {
    const payloadPart = parts[1];
    const padded = payloadPart + '='.repeat((4 - (payloadPart.length % 4 || 4)) % 4);
    const base64 = padded.replace(/-/g, '+').replace(/_/g, '/');
    const payloadJson = Buffer.from(base64, 'base64').toString('utf8');
    const payload = JSON.parse(payloadJson);
    return payload.preferred_username || payload.username || payload.sub || null;
  } catch {
    return null;
  }
}

function requireUser(req, res, next) {
  const username = getUser(req);

  if (!username) {
    return res.status(401).json({ error: 'Missing user. Set x-user header or user query param.' });
  }

  req.username = username;
  return next();
}

function requireNotesRead(req, res, next) {
  if (!canReadNotes(req.username)) {
    return res.status(403).json({ error: `User ${req.username} cannot read NOTES resources` });
  }

  return next();
}

function requireNotesWrite(req, res, next) {
  if (!canWriteNotes(req.username)) {
    return res.status(403).json({ error: `User ${req.username} cannot modify NOTES resources` });
  }

  return next();
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'notes-app' });
});

app.get('/authz/:username', (req, res) => {
  const username = req.params.username;
  const userGroups = groups.filter((g) => Array.isArray(g.members) && g.members.includes(username)).map((g) => g.name);
  return res.json({ username, groups: userGroups });
});

app.get('/projects', requireUser, requireNotesRead, (req, res) => {
  const visibleProjects = projects.filter((p) => canAccessProject(req.username, p.code));
  res.json(visibleProjects);
});

app.post('/projects', requireUser, requireNotesWrite, (req, res) => {
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

app.put('/projects/:id', requireUser, requireNotesRead, (req, res) => {
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

app.delete('/projects/:id', requireUser, requireNotesWrite, (req, res) => {
  const id = Number(req.params.id);
  const project = projects.find((p) => p.id === id);
  if (!project) {
    return res.status(404).json({ error: 'project not found' });
  }

  if (!canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${project.code}` });
  }

  projects = projects.filter((p) => p.id !== id);
  notes = notes.filter((n) => n.projectId !== id);
  return res.status(204).send();
});

app.get('/notes', requireUser, requireNotesRead, (req, res) => {
  const projectId = req.query.projectId ? Number(req.query.projectId) : null;
  if (!projectId) {
    const visibleNotes = notes.filter((n) => {
      const project = projects.find((p) => p.id === n.projectId);
      return project && canAccessProject(req.username, project.code);
    });
    return res.json(visibleNotes);
  }

  const project = projects.find((p) => p.id === projectId);
  if (!project) {
    return res.status(404).json({ error: 'project not found' });
  }

  if (!canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} is not assigned to project ${project.code}` });
  }

  return res.json(notes.filter((n) => n.projectId === projectId));
});

app.post('/notes', requireUser, requireNotesWrite, (req, res) => {
  const { title, content = '', projectId } = req.body;
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

  const nextId = notes.length ? Math.max(...notes.map((n) => n.id)) + 1 : 1;
  const note = { id: nextId, title, content, projectId: Number(projectId) };
  notes.push(note);
  return res.status(201).json(note);
});

app.put('/notes/:id', requireUser, requireNotesWrite, (req, res) => {
  const id = Number(req.params.id);
  const idx = notes.findIndex((n) => n.id === id);
  if (idx === -1) {
    return res.status(404).json({ error: 'note not found' });
  }

  const currentProject = projects.find((p) => p.id === notes[idx].projectId);
  if (!currentProject || !canAccessProject(req.username, currentProject.code)) {
    return res.status(403).json({ error: `User ${req.username} cannot modify this note` });
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

  notes[idx] = {
    ...notes[idx],
    title: req.body.title ?? notes[idx].title,
    content: req.body.content ?? notes[idx].content,
    projectId: req.body.projectId ? Number(req.body.projectId) : notes[idx].projectId
  };

  return res.json(notes[idx]);
});

app.delete('/notes/:id', requireUser, requireNotesWrite, (req, res) => {
  const id = Number(req.params.id);
  const note = notes.find((n) => n.id === id);
  if (!note) {
    return res.status(404).json({ error: 'note not found' });
  }

  const project = projects.find((p) => p.id === note.projectId);
  if (!project || !canAccessProject(req.username, project.code)) {
    return res.status(403).json({ error: `User ${req.username} cannot delete this note` });
  }

  notes = notes.filter((n) => n.id !== id);
  return res.status(204).send();
});

app.listen(port, () => {
  console.log(`notes-app listening on port ${port}`);
});
