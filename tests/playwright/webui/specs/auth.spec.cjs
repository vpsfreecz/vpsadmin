const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const {
  login,
  loginButton,
  logout,
  openWebuiLogin,
  submitCredentials,
} = require('../lib/pages/auth.cjs');

const fixtures = readFixtures();

test('anonymous webui loads', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveTitle(/vpsAdmin/);
  await expect(loginButton(page)).toHaveValue('Log in');
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

test('user login and logout work', async ({ page }) => {
  await login(page, fixtures.user);
  await expect(page.locator('#nav a[href="?page=adminvps"]')).toBeVisible();
  await logout(page, fixtures.user.username);
});
