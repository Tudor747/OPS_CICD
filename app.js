const express = require('express');
const app = express();

app.get('/', (_req, res) => res.type('text').send('My first manual deployment!\n'));
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

const server = app.listen(3000, '0.0.0.0', () => console.log('Listening on port 3000'));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
