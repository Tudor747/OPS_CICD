const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { once } = require('node:events');

test('HTTP routes respond and the server shuts down cleanly', async () => {
  const child = spawn(process.execPath, ['app.js'], { stdio: ['ignore', 'pipe', 'pipe'] });
  const exited = once(child, 'exit');
  let errors = '';
  child.stderr.on('data', chunk => { errors += chunk; });
  try {
    await Promise.race([
      once(child.stdout, 'data'),
      exited.then(() => { throw new Error(`Server exited: ${errors}`); }),
      new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Startup timed out')), 5000); timer.unref(); })
    ]);
    const home = await fetch('http://127.0.0.1:3000/');
    assert.equal(home.status, 200);
    assert.match(home.headers.get('content-type'), /text\/plain/);
    assert.ok((await home.text()).trim().length > 0);
    const health = await fetch('http://127.0.0.1:3000/health');
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { status: 'ok' });
    assert.equal((await fetch('http://127.0.0.1:3000/missing')).status, 404);
  } finally {
    child.kill('SIGTERM');
    await exited;
  }
});
