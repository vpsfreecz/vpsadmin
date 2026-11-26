const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../api/lib/vpsadmin/api/authentication/assets/appearance.js'), 'utf8');

function browser(incoming, saved, blocked = false) {
  const fields = [{ value: '' }];
  const links = [{ href: 'https://auth.example.test/oauth2/password-reset?client_id=client' }];
  const inputs = ['light', 'dark', 'auto'].map(value => ({ value, checked: false }));
  const controls = { hidden: true, addEventListener: (_, callback) => { controls.change = callback; } };
  const writes = [];
  let ready;
  const document = {
    documentElement: { dataset: {} },
    addEventListener: (_, callback) => { ready = callback; },
    querySelectorAll: selector => ({
      '[data-appearance-field]': fields,
      '[data-appearance-link]': links,
      '.appearance-controls input': inputs,
      '.appearance-controls': [controls]
    })[selector]
  };
  const window = {};
  vm.runInNewContext(source.replace('INITIAL_PREFERENCE', JSON.stringify(incoming)), {
    document, window, URL,
    location: { href: 'https://auth.example.test/_auth/oauth2/authorize', origin: 'https://auth.example.test' },
    localStorage: {
      getItem() { if (blocked) throw new Error('blocked'); return saved; },
      setItem(key, value) { if (blocked) throw new Error('blocked'); writes.push([key, value]); }
    }
  });
  return { document, ready, fields, inputs, links, controls, writes, window };
}

test('incoming theme applies before paint without overwriting the saved preference', () => {
  const page = browser('dark', 'light');
  assert.equal(page.document.documentElement.dataset.appearance, 'dark');
  assert.deepEqual(page.writes, []);
  page.ready();
  assert.equal(page.fields[0].value, 'dark');
  assert.equal(new URL(page.links[0].href).searchParams.get('theme'), 'dark');
  assert.equal(page.controls.hidden, false);
});

test('auto remains auto and explicit selection alone saves a preference', () => {
  const page = browser('auto', 'light');
  page.ready();
  assert.equal(page.inputs.find(input => input.checked).value, 'auto');
  page.controls.change({ target: { value: 'dark' } });
  assert.equal(page.fields[0].value, 'dark');
  assert.deepEqual(page.writes, [['vpsadmin.oauth.appearance.v1', 'dark']]);
  assert.equal(page.window.vpsadminAppearance.url('https://other.example.test/sign-in'), 'https://other.example.test/sign-in');
});

test('missing or invalid input uses local preference, then auto; blocked storage keeps current flow usable', () => {
  assert.equal(browser(null, 'dark').document.documentElement.dataset.appearance, 'dark');
  assert.equal(browser('unknown', 'unknown').document.documentElement.dataset.appearance, 'auto');
  const page = browser(null, 'dark', true);
  page.ready();
  page.controls.change({ target: { value: 'light' } });
  assert.equal(page.fields[0].value, 'light');
  assert.equal(new URL(page.links[0].href).searchParams.get('theme'), 'light');
  page.controls.change({ target: { value: '<script>' } });
  assert.equal(page.fields[0].value, 'light');
});
