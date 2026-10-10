'use strict';

const { createApp } = require('./app');

const port = Number(process.env.PORT) || 8080;
const server = createApp().listen(port, () => {
  console.log(`listening on :${port}`);
});

// Kubernetes sends SIGTERM on pod termination; drain connections before exiting.
function shutdown(signal) {
  console.log(`${signal} received, shutting down`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
