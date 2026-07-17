const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout, navLink } = require('../lib/pages/auth.cjs');
const { submitForm } = require('../lib/pages/webui.cjs');

const fixtures = readFixtures();
const expectedRevision = process.env.VPSADMIN_WEBUI_REVISION;
const hasExpectedRevision = /^[0-9a-f]{40}$/.test(expectedRevision || '');

function contentLink(page, href) {
  return page.locator(`#content-in a[href="${href}"]`);
}

function tableRowWithLink(page, href) {
  return page.locator('tr', {
    has: page.locator(`a[href="${href}"]`),
  });
}

test('user overview exposes read-only navigation and status data', async ({ page }) => {
  await login(page, fixtures.user);
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('#content-in h1')).toContainText('Overview');
  if (hasExpectedRevision) {
    await expect(page.locator('#slogan a')).toHaveText(expectedRevision.slice(0, 8));
    await expect(page.locator('#slogan a')).toHaveAttribute(
      'href',
      `https://github.com/vpsfreecz/vpsadmin/commit/${expectedRevision}`,
    );
  } else {
    await expect(page.locator('#slogan')).toContainText('Version: 4.1.0');
    await expect(page.locator('#slogan a')).toHaveCount(0);
  }
  await expect(page.locator('#content-in')).toContainText(fixtures.newsLog.message);
  await expect(page.locator('#content-in')).toContainText('Members total');
  await expect(page.locator('#content-in')).toContainText('VPS total');
  await expect(page.locator('#content-in')).toContainText('IPv4 left');
  await expect(contentLink(page, `?page=node&id=${fixtures.node.id}`)).toContainText(
    fixtures.node.name,
  );

  await expect(page.locator('#aside a[href="?page=outage&action=list"]')).toBeVisible();
  await expect(page.locator('#aside a[href="?page=monitoring&action=list"]')).toBeVisible();
  await expect(page.locator('#aside a[href="?page=oom_reports&action=list"]')).toBeVisible();
  await expect(page.locator('#aside a[href*="page=incidents&action=list"]')).toBeVisible();

  await logout(page, fixtures.user.username);
});

test('user can open node detail and reported system history', async ({ page }) => {
  await login(page, fixtures.user);
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await contentLink(page, `?page=node&id=${fixtures.node.id}`).click();

  await expect(page.locator('#content-in h1')).toContainText(`Node ${fixtures.node.domainName}`);
  await expect(page.locator('#content-in')).toContainText(fixtures.location.label);
  await expect(page.locator('#content-in')).toContainText('Storage pools');

  const systemHistoryHref = `?page=node&action=system_history&id=${fixtures.node.id}`;
  await expect(page.locator(`#aside a[href="${systemHistoryHref}"]`)).toBeVisible();
  await page.locator(`#aside a[href="${systemHistoryHref}"]`).click();
  await expect(page.locator('#content-in h1')).toContainText(
    `System history: ${fixtures.node.domainName}`,
  );
  await expect(page.locator('#content-in .page-description')).toHaveCount(0);
  await expect(page.locator('#node-system-history')).toBeVisible();
  await expect(page.locator('#node-system-history tr').first().locator('th')).toHaveCount(5);
  await expect(page.locator('#node-system-history')).toContainText('current');
  await expect(page.locator('#node-system-history')).toContainText('v2');
  await expect(page.locator('#node-system-history')).not.toContainText('cgroup v2');

  await logout(page, fixtures.user.username);
});

test('user object history renders filtered readonly events', async ({ page }) => {
  await login(page, fixtures.user);
  await page.goto(
    `/?page=history&return_url=&list=1&object=User&object_id=${fixtures.user.id}&event_type=${fixtures.objectHistory.eventType}`,
    { waitUntil: 'domcontentloaded' },
  );

  await expect(page.locator('#content-in h1')).toContainText('Object history');

  const filterForm = page.locator('form[name="user-session-filter"]').first();
  await expect(filterForm).toBeVisible();
  await expect(filterForm.locator('input[name="user"]')).toHaveCount(0);
  await expect(filterForm.locator('input[name="object"]')).toHaveValue('User');
  await expect(filterForm.locator('input[name="object_id"]')).toHaveValue(
    String(fixtures.user.id),
  );
  await expect(filterForm.locator('input[name="event_type"]')).toHaveValue(
    fixtures.objectHistory.eventType,
  );

  const row = page.locator('tr', { hasText: fixtures.objectHistory.eventType }).first();
  await expect(row).toContainText(`User ${fixtures.user.id}`);

  await logout(page, fixtures.user.username);
});

test('user transaction log opens and can filter to an owned chain', async ({ page }) => {
  await login(page, fixtures.user);
  await expect(navLink(page, '?page=transactions')).toBeVisible();
  await navLink(page, '?page=transactions').click();

  await expect(page.locator('#content-in h1')).toContainText('Transaction chains');

  const filterForm = page.locator('form[name="vps-filter"]').first();
  await expect(filterForm).toBeVisible();
  await filterForm.locator('input[name="name"]').fill(fixtures.transactionChain.name);
  await submitForm(filterForm);

  const chainHref = `?page=transactions&chain=${fixtures.transactionChain.id}`;
  const row = tableRowWithLink(page, chainHref).first();
  await expect(row).toHaveClass(/ok/);
  await expect(row).toContainText(fixtures.transactionChain.label);
  await expect(row).toContainText('100');

  await row.locator(`a[href="${chainHref}"]`).first().click();
  await expect(page.locator('#content-in')).toContainText(
    `Transaction chain #${fixtures.transactionChain.id}`,
  );
  await expect(page.locator('form[name="transaction-filter"]').first()).toBeVisible();
  await expect(page.locator('#content-in')).toContainText(
    String(fixtures.transactionChain.transactionId),
  );
  await expect(page.locator('#content-in')).toContainText(
    fixtures.transactionChain.transactionLabel,
  );

  await logout(page, fixtures.user.username);
});

test('admin overview exposes edit and node-detail links', async ({ page }) => {
  await login(page, fixtures.admin);
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await expect(contentLink(page, '?page=cluster&action=sysconfig')).toContainText('[edit]');
  await expect(contentLink(page, `?page=node&id=${fixtures.node.id}`)).toContainText(
    fixtures.node.name,
  );

  await contentLink(page, `?page=node&id=${fixtures.node.id}`).click();
  await expect(page.locator('#content-in h1')).toContainText(`Node ${fixtures.node.domainName}`);

  await logout(page, fixtures.admin.username);
});

test('admin transaction log shows admin filters and user column', async ({ page }) => {
  await login(page, fixtures.admin);
  await page.goto('/?page=transactions', { waitUntil: 'domcontentloaded' });

  const filterForm = page.locator('form[name="vps-filter"]').first();
  await expect(filterForm.locator('input[name="user"]')).toBeVisible();
  await filterForm.locator('input[name="user"]').fill(String(fixtures.user.id));
  await filterForm.locator('input[name="name"]').fill(fixtures.transactionChain.name);
  await submitForm(filterForm);

  const chainHref = `?page=transactions&chain=${fixtures.transactionChain.id}`;
  const row = tableRowWithLink(page, chainHref).first();
  await expect(row).toHaveClass(/ok/);
  await expect(row).toContainText(`User ${fixtures.user.id}`);
  await expect(row).toContainText(fixtures.transactionChain.label);
  await expect(row).toContainText('100');

  await logout(page, fixtures.admin.username);
});
