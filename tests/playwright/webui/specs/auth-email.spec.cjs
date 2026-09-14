const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const {
  logout,
  logoutButton,
  openWebuiLogin,
  submitCredentials,
} = require('../lib/pages/auth.cjs');
const { expectNotification } = require('../lib/pages/webui.cjs');

const fixtures = readFixtures();
const webuiBaseURL = process.env.WEBUI_BASE_URL || 'http://webui.vpsadmin.test';

test('email verification protects a new browser and preserves known-device login', async ({ browser, request }) => {
  const account = fixtures.emailVerification;
  const known = await browser.newContext({ baseURL: webuiBaseURL, ignoreHTTPSErrors: true });
  const page = await known.newPage();
  async function secureCredentials(target) {
    await openWebuiLogin(target, account.username);
    await target.goto(target.url().replace(/^http:/, 'https:'));
    await submitCredentials(target, account.username, account.password);
  }
  await secureCredentials(page);
  await expect(logoutButton(page)).toHaveValue(
    new RegExp(`Logout \\(${account.username}\\)`),
    { timeout: 60000 },
  );
  await page.goto(`/?page=adminm&action=edit&id=${account.id}`, { waitUntil: 'domcontentloaded' });
  const form = page.locator('form[action*="action=edit_email_verification"]');
  await expect(page.locator('[data-vpsadmin-doc-id="member.email-verification"]')).toBeVisible();
  await form.locator('input[name="enable_new_device_email_verification"]').check();
  await form.locator('input[type="submit"]').click();
  await expect(page.locator('#perex')).toContainText('User update failed');
  await page.goto(`/?page=adminm&action=edit&id=${account.id}`, { waitUntil: 'domcontentloaded' });
  await expect(form.locator('input[name="enable_new_device_email_verification"]')).not.toBeChecked();
  await form.locator('input[name="enable_new_device_email_verification"]').check();
  await form.locator('input[name="password"]').fill(account.password);
  await form.locator('input[type="submit"]').click();
  await expectNotification(page, 'Email verification settings updated');
  await expect(form.locator('input[name="enable_new_device_email_verification"]')).toBeChecked();
  await logout(page, account.username);
  await secureCredentials(page);
  await expect(logoutButton(page)).toHaveValue(
    new RegExp(`Logout \\(${account.username}\\)`),
    { timeout: 60000 },
  );

  const fresh = await browser.newContext({ baseURL: webuiBaseURL, ignoreHTTPSErrors: true });
  const unknown = await fresh.newPage();
  try {
    await secureCredentials(unknown);
    const codeField = unknown.getByLabel('Email verification code');
    await expect(codeField).toBeVisible();
    await expect(unknown.locator('body')).toContainText('30 minutes');
    await expect(codeField).toHaveAttribute('autocomplete', 'one-time-code');
    await unknown.getByRole('button', { name: 'Send another code' }).click();
    await expect(unknown.locator('.alert-danger')).toContainText('wait at least a minute');

    const mailResponse = await request.get('http://api.vpsadmin.test/v7.0/mail_logs', {
      headers: {
        Authorization: `Basic ${Buffer.from(`${fixtures.admin.username}:${fixtures.admin.password}`).toString('base64')}`,
        Accept: 'application/json',
      },
      params: { 'mail_log[limit]': '1000' },
    });
    expect(mailResponse.ok()).toBe(true);
    const mails = (await mailResponse.json()).response.mail_logs;
    const mail = mails.filter((item) => item.to === account.email && /^\d{6}$/m.test(item.text_plain || ''))
      .sort((a, b) => b.id - a.id)[0];
    expect(mail).toBeTruthy();
    const code = mail.text_plain.match(/^\d{6}$/m)[0];
    await codeField.fill(code === '000000' ? '000001' : '000000');
    await unknown.getByRole('button', { name: 'Verify and sign in' }).click();
    await expect(unknown.locator('.alert-danger')).toContainText('The email code is incorrect.');
    await codeField.fill(code);
    await unknown.getByRole('button', { name: 'Verify and sign in' }).click();
    await expect(logoutButton(unknown)).toHaveValue(
      new RegExp(`Logout \\(${account.username}\\)`),
      { timeout: 60000 },
    );
  } finally {
    await fresh.close();
    await known.close();
  }
});
