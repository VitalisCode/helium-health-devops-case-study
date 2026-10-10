'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');

let server;
let base;

test.before(async () => {
  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      base = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
});

test.after(() => server.close());

test('GET /healthz returns ok', async () => {
  const res = await fetch(`${base}/healthz`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { status: 'ok' });
});

test('GET /readyz returns ready', async () => {
  const res = await fetch(`${base}/readyz`);
  assert.strictEqual(res.status, 200);
});

test('POST then GET an item', async () => {
  const created = await fetch(`${base}/api/v1/items`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'first' }),
  });
  assert.strictEqual(created.status, 201);
  const item = await created.json();
  const fetched = await fetch(`${base}/api/v1/items/${item.id}`);
  assert.strictEqual(fetched.status, 200);
  assert.strictEqual((await fetched.json()).name, 'first');
});

test('POST without name is rejected', async () => {
  const res = await fetch(`${base}/api/v1/items`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.strictEqual(res.status, 400);
});

test('POST with malformed JSON is rejected', async () => {
  const res = await fetch(`${base}/api/v1/items`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{"name":',
  });
  assert.strictEqual(res.status, 400);
  assert.deepStrictEqual(await res.json(), { error: 'invalid JSON' });
});

test('unknown item returns 404', async () => {
  const res = await fetch(`${base}/api/v1/items/9999`);
  assert.strictEqual(res.status, 404);
});
