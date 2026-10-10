'use strict';

const express = require('express');

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '100kb' }));

  // In-memory store: good enough for a demo service with no database.
  const items = new Map();
  let nextId = 1;

  // Liveness: process is up. Readiness: ready for traffic (no deps here, so same check).
  app.get('/healthz', (_req, res) => res.status(200).json({ status: 'ok' }));
  app.get('/readyz', (_req, res) => res.status(200).json({ status: 'ready' }));

  app.get('/api/v1/info', (_req, res) => {
    res.json({
      service: process.env.SERVICE_NAME || 'patient-notes-api',
      environment: process.env.APP_ENV || 'local',
      version: process.env.APP_VERSION || 'dev',
    });
  });

  app.get('/api/v1/items', (_req, res) => res.json([...items.values()]));

  app.post('/api/v1/items', (req, res) => {
    const { name } = req.body || {};
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'name is required' });
    }
    const item = { id: nextId++, name: name.trim() };
    items.set(item.id, item);
    return res.status(201).json(item);
  });

  app.get('/api/v1/items/:id', (req, res) => {
    const item = items.get(Number(req.params.id));
    if (!item) return res.status(404).json({ error: 'not found' });
    return res.json(item);
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    console.error(err);
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

module.exports = { createApp };
