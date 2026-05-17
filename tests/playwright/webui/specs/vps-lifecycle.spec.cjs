const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { gotoVpsDetail } = require('../lib/pages/webui.cjs');
const {
  createVps,
  deployPublicKey,
  reinstallVps,
  resetRootPassword,
  runDetailAction,
  setDnsResolverMode,
  setHostname,
} = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();

test.describe.serial('VPS browser lifecycle', () => {
  let vpsId;
  let hostname;

  test('user creates and manages a VPS', async ({ page }) => {
    hostname = `webui-vps-${Date.now().toString(36)}`;

    await login(page, fixtures.user);

    vpsId = await createVps(page, fixtures, hostname);

    await runDetailAction(page, vpsId, 'stop', 'Stop VPS', 'stopped');
    await runDetailAction(page, vpsId, 'start', 'Start of', 'running');
    await runDetailAction(page, vpsId, 'restart', 'Restart of', 'running');

    await resetRootPassword(page, vpsId);
    await deployPublicKey(page, vpsId, fixtures.user.publicKey.id);
    await setDnsResolverMode(page, vpsId, 'manual');

    hostname = `${hostname}-renamed`;
    await setHostname(page, vpsId, hostname);

    await reinstallVps(page, vpsId, fixtures);
    await logout(page, fixtures.user.username);
  });

  test('admin sees admin-only VPS data and actions', async ({ page }) => {
    expect(vpsId).toBeTruthy();

    await login(page, fixtures.admin);

    await page.goto('/?page=adminvps&action=list', { waitUntil: 'domcontentloaded' });
    const filterForm = page.locator('form[name="vps-filter"]', {
      has: page.locator('input[name="user"]'),
    });
    await expect(filterForm).toBeVisible();
    await expect(filterForm.locator('input[name="user"]')).toBeVisible();
    await expect(filterForm.locator('select[name="node"]')).toBeVisible();

    await gotoVpsDetail(page, vpsId);
    await expect(page.locator('#content-in h1')).toContainText('[Admin mode]');
    await expect(page.locator('table.table-style01 tr', { hasText: 'Owner:' })).toContainText(
      fixtures.user.username,
    );
    await expect(page.locator('table.table-style01 tr', { hasText: 'Node:' })).toBeVisible();
    await expect(page.locator('#aside a', { hasText: 'Migrate VPS' })).toBeVisible();
    await expect(page.locator('#aside a', { hasText: 'Change owner' })).toBeVisible();
    await expect(page.locator('#aside a', { hasText: 'Replace VPS' })).toBeVisible();
    await expect(page.locator('input[name="cpu_limit"]')).toBeVisible();
    await expect(page.locator('select[name="admin_lock_type"]')).toBeVisible();
    await expect(page.locator('#content-in h2', { hasText: /Disable network|Enable network/ })).toBeVisible();
    await expect(page.locator('#content-in h2', { hasText: 'Auto-Start' })).toBeVisible();

    await logout(page, fixtures.admin.username);
  });

  test('normal user does not see admin-only VPS controls', async ({ page }) => {
    expect(vpsId).toBeTruthy();

    await login(page, fixtures.user);
    await gotoVpsDetail(page, vpsId);

    await expect(page.locator('#content-in h1')).toContainText('[User mode]');
    await expect(page.locator('#aside a', { hasText: 'Migrate VPS' })).toHaveCount(0);
    await expect(page.locator('#aside a', { hasText: 'Change owner' })).toHaveCount(0);
    await expect(page.locator('#aside a', { hasText: 'Replace VPS' })).toHaveCount(0);
    await expect(page.locator('input[name="cpu_limit"]')).toHaveCount(0);
    await expect(page.locator('select[name="admin_lock_type"]')).toHaveCount(0);
    await expect(page.locator('#content-in h2', { hasText: 'Auto-Start' })).toHaveCount(0);

    await logout(page, fixtures.user.username);
  });
});
