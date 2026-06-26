const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const {
  accountMenuLink,
  clickAccountMenuLink,
  login,
  loginButton,
  logout,
  logoutButton,
  navLink,
  openAccountMenu,
  openWebuiLogin,
  submitCredentials,
} = require('../lib/pages/auth.cjs');
const {
  memberRow,
  submitMemberListFilters,
} = require('../lib/pages/users.cjs');

const fixtures = readFixtures();

async function expectNavLinks(page, hrefs) {
  for (const href of hrefs) {
    await expect(navLink(page, href)).toBeVisible();
  }
}

test('anonymous webui loads', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveTitle(/vpsAdmin/);
  await expect(loginButton(page)).toHaveValue('Log in');
});

test('anonymous about page renders', async ({ page }) => {
  await page.goto('/?page=about', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('#perex')).toContainText('vpsAdmin');
  await expect(page.locator('#perex')).toContainText('Web-admin interface for vpsAdminOS');
});

test('anonymous log page renders news log', async ({ page }) => {
  await page.goto('/?page=log', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('#content-in h1')).toContainText('Log');
  await expect(page.locator('body')).toContainText(fixtures.newsLog.message);
});

test('OAuth callback error displays authentication error', async ({ page }) => {
  await page.goto(
    '/?page=login&action=callback&error=access_denied&error_description=Denied+by+webui+test',
    { waitUntil: 'domcontentloaded' },
  );

  await expect(page.locator('#perex')).toContainText('Authentication error');
  await expect(page.locator('#perex')).toContainText('Denied by webui test');
});

test('invalid OAuth password stays on auth form', async ({ page }) => {
  await openWebuiLogin(page);
  await submitCredentials(page, fixtures.admin.username, 'wrong-password');

  await expect(page.locator('.alert-danger')).toContainText('invalid user or password');
  await expect(page.locator('input[name="user"]')).toHaveValue(fixtures.admin.username);
  await expect(page).toHaveURL(/api\.vpsadmin\.test/);
});

test('admin login and logout work', async ({ page }) => {
  await login(page, fixtures.admin);
  await expect(page.locator('#nav a[href="?page=cluster"]')).toBeVisible();
  await logout(page, fixtures.admin.username);
});

test('admin top-level menu shows admin pages', async ({ page }) => {
  await login(page, fixtures.admin);

  await expectNavLinks(page, [
    '?page=',
    '?page=adminm',
    '?page=adminvps',
    '?page=backup',
    '?page=nas',
    '?page=export',
    '?page=networking',
    '?page=dns',
    '?page=cluster',
    '?page=transactions',
  ]);
  await expect(navLink(page, '?page=userns')).toHaveCount(0);

  await logout(page, fixtures.admin.username);
});

test('user login and logout work', async ({ page }) => {
  await login(page, fixtures.user);
  await expect(page.locator('#nav a[href="?page=adminvps"]')).toBeVisible();
  await logout(page, fixtures.user.username);
});

test('user top-level menu shows user pages and hides cluster', async ({ page }) => {
  await login(page, fixtures.user);

  await expectNavLinks(page, [
    '?page=',
    '?page=adminm',
    '?page=adminvps',
    '?page=backup',
    '?page=nas',
    '?page=export',
    '?page=userns',
    '?page=networking',
    '?page=dns',
    '?page=transactions',
  ]);
  await expect(navLink(page, '?page=cluster')).toHaveCount(0);

  await logout(page, fixtures.user.username);
});

test('user direct access to cluster is forbidden', async ({ page }) => {
  await login(page, fixtures.user);
  await page.goto('/?page=cluster', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('#perex')).toContainText('Access forbidden');
  await expect(navLink(page, '?page=cluster')).toHaveCount(0);

  await logout(page, fixtures.user.username);
});

test('switch user action logs out to OAuth form', async ({ page }) => {
  await login(page, fixtures.user);
  await clickAccountMenuLink(page, 'Switch user');

  await expect(page).toHaveURL(/api\.vpsadmin\.test/);
  await expect(page.locator('input[name="user"]')).toBeVisible();
  await expect(page.locator('input[name="user"]')).toHaveValue('');
});

test('remembered login quick switch pre-fills OAuth username', async ({ page }) => {
  await login(page, fixtures.user);
  await logout(page, fixtures.user.username);

  await login(page, fixtures.admin);
  await openAccountMenu(page);
  await expect(accountMenuLink(page, `Switch to ${fixtures.user.username}`)).toBeVisible();
  await accountMenuLink(page, `Switch to ${fixtures.user.username}`).click();

  await expect(page).toHaveURL(/api\.vpsadmin\.test/);
  await expect(page.locator('input[name="user"]')).toHaveValue(fixtures.user.username);
});

test('admin can drop and regain privileges', async ({ page }) => {
  await login(page, fixtures.admin);

  await page.goto(`/?page=login&action=drop_admin&next=${encodeURIComponent('/?page=cluster')}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#perex')).toContainText('Access forbidden');
  await expect(navLink(page, '?page=cluster')).toHaveCount(0);

  await page.goto(`/?page=login&action=regain_admin&next=${encodeURIComponent('/?page=cluster')}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(navLink(page, '?page=cluster')).toBeVisible();
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${fixtures.admin.username}\\)`));

  await logout(page, fixtures.admin.username);
});

test('admin can switch into user context and regain admin', async ({ page }) => {
  await login(page, fixtures.admin);

  await page.goto(`/?page=adminm&action=edit&id=${fixtures.user.id}`, {
    waitUntil: 'domcontentloaded',
  });
  const switchForm = page.locator('form[action="?page=login&action=switch_context"]', {
    has: page.locator(`input[name="m_id"][value="${fixtures.user.id}"]`),
  }).first();
  await expect(switchForm).toBeVisible();
  await switchForm.locator('input[name="next"]').evaluate((input) => {
    input.value = '/?page=';
  });
  await switchForm.locator('input[type="image"], input[type="submit"], button[type="submit"]').first().click();
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${fixtures.user.username}\\)`));
  await expect(navLink(page, '?page=adminvps')).toBeVisible();
  await expect(navLink(page, '?page=cluster')).toHaveCount(0);

  await page.goto(`/?page=login&action=regain_admin&next=${encodeURIComponent('/?page=cluster')}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${fixtures.admin.username}\\)`));
  await expect(navLink(page, '?page=cluster')).toBeVisible();

  await logout(page, fixtures.admin.username);
});

test('admin can switch into user context from members list', async ({ page }) => {
  const target = fixtures.adminMembers.managed;

  await login(page, fixtures.admin);

  await submitMemberListFilters(page, {
    limit: 1,
    fromId: target.id - 1,
    login: target.username,
  });

  const row = memberRow(page, target.id);
  await expect(row).toContainText(target.username);

  const switchForm = row.locator('form[action="?page=login&action=switch_context"]', {
    has: page.locator(`input[name="m_id"][value="${target.id}"]`),
  }).first();
  await expect(switchForm).toContainText(target.username);
  await switchForm.locator('input[name="next"]').evaluate((input) => {
    input.value = '/?page=';
  });
  await switchForm.locator('button[type="submit"]').click();
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${target.username}\\)`));
  await expect(navLink(page, '?page=cluster')).toHaveCount(0);

  await page.goto(`/?page=login&action=regain_admin&next=${encodeURIComponent('/?page=cluster')}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${fixtures.admin.username}\\)`));
  await expect(navLink(page, '?page=cluster')).toBeVisible();

  await logout(page, fixtures.admin.username);
});
