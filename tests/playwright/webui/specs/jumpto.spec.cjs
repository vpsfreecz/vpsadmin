const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');

const fixtures = readFixtures();

async function submitJumpto(page, query) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const form = page.locator('form#jumpto');
  await expect(form).toBeVisible();
  await form.locator('input[name="search"]').fill(query);
  await form.locator('input[type="submit"]').click();

  await expect(page.locator('#content-in h1')).toContainText('Found these bros');
}

function resultRow(page, resource, href) {
  return page
    .locator('#content-in table.table-style01 tr', {
      has: page.locator(`a[href="${href}"]`),
    })
    .filter({ hasText: resource })
    .first();
}

async function expectResult(page, resource, href, value) {
  const row = resultRow(page, resource, href);

  await expect(row).toBeVisible();
  await expect(row.locator('td').first()).toHaveText(resource);
  await expect(row.locator(`a[href="${href}"]`)).toBeVisible();

  if (value) {
    await expect(row).toContainText(value);
  }
}

test('normal user cannot access admin jumpto search', async ({ page }) => {
  await login(page, fixtures.user);
  await page.goto('/?page=jumpto&search=webui', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('#perex h1')).toContainText('Access forbidden');
  await expect(page.locator('form#jumpto')).toHaveCount(0);

  await logout(page, fixtures.user.username);
});

test('admin jumpto finds named user, VPS, and DNS resources', async ({ page }) => {
  await login(page, fixtures.admin);
  await submitJumpto(page, fixtures.jumpto.textSearch);

  await expectResult(
    page,
    'User',
    `?page=adminm&action=edit&id=${fixtures.jumpto.user.id}`,
    fixtures.jumpto.user.login,
  );
  await expectResult(
    page,
    'Vps',
    `?page=adminvps&action=info&veid=${fixtures.jumpto.vps.id}`,
    fixtures.jumpto.vps.hostname,
  );
  await expectResult(
    page,
    'DnsZone',
    `?page=dns&action=zone_show&id=${fixtures.jumpto.dnsZone.id}`,
    fixtures.jumpto.dnsZone.name,
  );

  await logout(page, fixtures.admin.username);
});

test('admin jumpto finds network, IP address, and export resources by address', async ({
  page,
}) => {
  await login(page, fixtures.admin);
  await submitJumpto(page, fixtures.jumpto.ipSearch);

  await expectResult(
    page,
    'Network',
    `?page=cluster&action=network_locations&network=${fixtures.jumpto.network.id}`,
    fixtures.jumpto.network.cidr,
  );
  await expectResult(
    page,
    'IpAddress',
    `?page=networking&action=route_edit&id=${fixtures.jumpto.ipAddress.id}`,
    fixtures.jumpto.ipAddress.addr,
  );
  await expectResult(
    page,
    'Export',
    `?page=export&action=edit&export=${fixtures.jumpto.export.id}`,
    fixtures.jumpto.ipAddress.addr,
  );

  await logout(page, fixtures.admin.username);
});

test('admin jumpto finds transaction chains by id', async ({ page }) => {
  await login(page, fixtures.admin);
  await submitJumpto(page, String(fixtures.transactionChain.id));

  await expectResult(
    page,
    'TransactionChain',
    `?page=transactions&chain=${fixtures.transactionChain.id}`,
    String(fixtures.transactionChain.id),
  );

  await logout(page, fixtures.admin.username);
});
