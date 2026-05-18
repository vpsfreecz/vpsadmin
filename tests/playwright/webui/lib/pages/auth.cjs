const { expect } = require('@playwright/test');

const loginButton = (page) =>
  page.locator('form[action="?page=login&action=login"] input[type="submit"]');

const logoutButton = (page) =>
  page.locator('form[action="?page=login&action=logout"] input[type="submit"]');

const navLink = (page, href) => page.locator(`#nav a[href="${href}"]`);

const accountMenuLink = (page, text) =>
  page.locator('#logout .account-menu a', { hasText: text });

async function openWebuiLogin(page, user) {
  const params = user ? `?page=login&action=login&user=${encodeURIComponent(user)}` : '/';

  if (user) {
    await page.goto(params, { waitUntil: 'domcontentloaded' });
  } else {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(loginButton(page)).toHaveValue('Log in');
    await loginButton(page).click();
  }

  await expect(page).toHaveURL(/api\.vpsadmin\.test/);
  await expect(page.locator('input[name="user"]')).toBeVisible();
}

async function submitCredentials(page, username, password) {
  await page.locator('input[name="user"]').fill(username);
  await page.locator('input[name="password"]').fill(password);
  await page.locator('input[name="login_credentials"]').click({ noWaitAfter: true });
}

async function login(page, account) {
  await openWebuiLogin(page, account.username);
  await submitCredentials(page, account.username, account.password);
  try {
    await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${account.username}\\)`));
  } catch (error) {
    const body = await page.locator('body').innerText({ timeout: 1000 }).catch(() => '');
    throw new Error(
      [
        `Login as ${account.username} did not reach the web UI.`,
        `URL: ${page.url()}`,
        body.slice(0, 2000),
        error.message,
      ].join('\n\n'),
    );
  }
}

async function logout(page, username) {
  await expect(logoutButton(page)).toHaveValue(new RegExp(`Logout \\(${username}\\)`));
  await logoutButton(page).click();
  await expect(loginButton(page)).toHaveValue('Log in');
}

async function openAccountMenu(page) {
  await page.locator('#logout').hover();
  await expect(page.locator('#logout .account-menu')).toBeVisible();
}

async function clickAccountMenuLink(page, text) {
  await openAccountMenu(page);
  await accountMenuLink(page, text).click();
}

module.exports = {
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
};
