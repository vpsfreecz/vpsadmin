const crypto = require('crypto');
const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  detailValue,
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  actionLink,
  changePassword,
  gotoMemberEdit,
  gotoMemberList,
  linkParam,
  memberActionUrl,
  memberRow,
  setCheckbox,
  submitAuthSettings,
  submitCurrentMemberSettings,
  submitMfaEnabled,
  submitSessionControl,
} = require('../lib/pages/users.cjs');

const fixtures = readFixtures();
const webuiBaseURL = process.env.WEBUI_BASE_URL || 'http://webui.vpsadmin.test';

const selfServicePublicKey =
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICdl1OmUwRKSkYjismjOiW46qAeMkIFwYfKNNSUaIbC6 webui-users-self-service@test';

const timeZoneTip = (page) =>
  page.locator('.webui-tip[data-webui-tip-id="time_zone_settings_v1"]');

async function withTimeZonePage(browser, timezoneId, callback) {
  const context = await browser.newContext({
    baseURL: webuiBaseURL,
    timezoneId,
  });
  const page = await context.newPage();

  try {
    await callback(page);
  } finally {
    await context.close();
  }
}

function rowWithText(page, text) {
  return page.locator('table.table-style01 tr', { hasText: text }).first();
}

function base32Decode(value) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const clean = value.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = '';
  const bytes = [];

  for (const char of clean) {
    const index = alphabet.indexOf(char);

    if (index === -1) {
      throw new Error(`Invalid base32 character ${char}`);
    }

    bits += index.toString(2).padStart(5, '0');

    while (bits.length >= 8) {
      bytes.push(Number.parseInt(bits.slice(0, 8), 2));
      bits = bits.slice(8);
    }
  }

  return Buffer.from(bytes);
}

function totpCode(secret, now = Date.now()) {
  const counter = Math.floor(now / 1000 / 30);
  const buffer = Buffer.alloc(8);
  buffer.writeUInt32BE(Math.floor(counter / 0x100000000), 0);
  buffer.writeUInt32BE(counter >>> 0, 4);

  const hmac = crypto.createHmac('sha1', base32Decode(secret)).update(buffer).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binary = (
    ((hmac[offset] & 0x7f) << 24)
    | ((hmac[offset + 1] & 0xff) << 16)
    | ((hmac[offset + 2] & 0xff) << 8)
    | (hmac[offset + 3] & 0xff)
  );

  return String(binary % 1_000_000).padStart(6, '0');
}

async function waitForStableTotpWindow(page) {
  const phase = Math.floor(Date.now() / 1000) % 30;

  if (phase >= 25) {
    await page.waitForTimeout((31 - phase) * 1000);
  }
}

async function expectAdminOnlyActionHidden(page, url, forbiddenText, selector = null) {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).not.toContainText(forbiddenText);

  if (selector) {
    await expect(page.locator(selector)).toHaveCount(0);
  }
}

test.describe.serial('user members self-service browser coverage', () => {
  test('time zone tip can apply browser time zone', async ({ browser }) => {
    const account = fixtures.timeZoneTip.set;

    await withTimeZonePage(browser, 'Europe/Prague', async (page) => {
      await login(page, account);

      const tip = timeZoneTip(page);
      await expect(tip).toBeVisible();
      await expect(tip).toContainText('Europe/Prague');

      await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
        tip.locator('button[data-webui-tip-action="use-browser-time-zone"]').click(),
      ]);
      await expect(timeZoneTip(page)).toHaveCount(0);
      await expect.poll(
        () => page.evaluate(() => window.vpsAdmin.user.timeZone),
      ).toBe('Europe/Prague');

      await gotoMemberEdit(page, account.id);
      await expect(
        formByAction(page, 'action=edit_member').locator('select[name="time_zone"]'),
      ).toHaveValue('Europe/Prague');

      await logout(page, account.username);
    });
  });

  test('time zone tip can be dismissed permanently', async ({ browser }) => {
    const account = fixtures.timeZoneTip.dismiss;

    await withTimeZonePage(browser, 'Europe/Prague', async (page) => {
      await login(page, account);

      const tip = timeZoneTip(page);
      await expect(tip).toBeVisible();
      await tip.locator('button[data-webui-tip-action="dismiss"]').last().click();
      await expect(tip).toBeHidden();

      await page.reload({ waitUntil: 'domcontentloaded' });
      await expect(timeZoneTip(page)).toHaveCount(0);

      await gotoMemberEdit(page, account.id);
      await expect(
        formByAction(page, 'action=edit_member').locator('select[name="time_zone"]'),
      ).toHaveValue('');

      await logout(page, account.username);
    });
  });

  test('time zone tip stays hidden when browser uses server default', async ({ browser }) => {
    const account = fixtures.timeZoneTip.utc;

    await withTimeZonePage(browser, 'UTC', async (page) => {
      await login(page, account);

      await expect(timeZoneTip(page)).toBeHidden();
      await logout(page, account.username);
    });
  });

  test('time zone tip stays hidden when browser zone is equivalent to server default', async ({ browser }) => {
    const account = fixtures.timeZoneTip.utc;

    await withTimeZonePage(browser, 'Africa/Abidjan', async (page) => {
      await login(page, account);

      await expect(timeZoneTip(page)).toBeHidden();
      await logout(page, account.username);
    });
  });

  test('user member list and profile forms stay in self-service mode', async ({ page }) => {
    await login(page, fixtures.user);

    await gotoMemberList(page);
    await expect(page.locator('form[name="user-filter"]')).toHaveCount(0);
    await expect(page.locator('#content-in')).toContainText(fixtures.user.username);
    await expect(page.locator('#content-in')).not.toContainText(fixtures.users.secondary.username);
    await expect(memberRow(page, fixtures.user.id)).toBeVisible();
    await expect(actionLink(page, 'new')).toHaveCount(0);
    await expect(actionLink(page, 'delete', { id: fixtures.user.id })).toHaveCount(0);
    await expect(page.locator('img[title="Cannot delete yourself"]')).toBeVisible();

    await page.goto(memberActionUrl('edit', fixtures.users.secondary.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(fixtures.user.username);
    await expect(page.locator('#content-in')).not.toContainText(fixtures.users.secondary.username);
    await expect(
      formByAction(page, `action=edit_member&id=${fixtures.user.id}`),
    ).toBeVisible();

    await expect(formByAction(page, 'action=edit_personal')).toBeVisible();
    await expect(page.locator('input[name="change_reason"]')).toBeVisible();

    await submitCurrentMemberSettings(page, fixtures.user.id);
    await submitAuthSettings(page, fixtures.user.id, {
      enable_basic_auth: false,
      enable_token_auth: false,
      enable_new_login_notification: false,
    });
    await submitAuthSettings(page, fixtures.user.id, {
      enable_basic_auth: true,
      enable_token_auth: true,
      enable_new_login_notification: true,
    });
    await submitSessionControl(page, fixtures.user.id, {
      enableSingleSignOn: false,
      preferredSessionLength: 5,
      preferredLogoutAll: true,
    });
    await submitSessionControl(page, fixtures.user.id, {
      enableSingleSignOn: true,
      preferredSessionLength: 20,
      preferredLogoutAll: false,
    });
    await submitMfaEnabled(page, fixtures.user.id, true);
    await submitMfaEnabled(page, fixtures.user.id, false);

    await logout(page, fixtures.user.username);
  });

  test('user password change restores the fixture password', async ({ page }) => {
    const temporaryPassword = `webuiUserPassword2${Date.now().toString(36)}`;
    let activePassword = fixtures.user.password;

    await login(page, fixtures.user);

    try {
      await changePassword(page, fixtures.user.id, fixtures.user.password, temporaryPassword);
      activePassword = temporaryPassword;
      await changePassword(page, fixtures.user.id, temporaryPassword, fixtures.user.password);
      activePassword = fixtures.user.password;
    } finally {
      if (activePassword !== fixtures.user.password) {
        await changePassword(page, fixtures.user.id, activePassword, fixtures.user.password);
      }
    }

    await logout(page, fixtures.user.username);
    await login(page, fixtures.user);
    await logout(page, fixtures.user.username);
  });

  test('user public keys can be added, edited, and deleted', async ({ page }) => {
    const label = 'Webui Self-Service Key';
    const editedLabel = 'Webui Self-Service Key Edited';

    await login(page, fixtures.user);
    await page.goto(memberActionUrl('pubkeys', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Public keys');
    await expect(page.locator('#content-in')).toContainText(fixtures.user.publicKey.label);

    await actionLink(page, 'pubkey_add').click();
    const addForm = formByAction(page, 'action=pubkey_add');
    await addForm.locator('input[name="label"]').fill(label);
    await addForm.locator('textarea[name="key"]').fill(selfServicePublicKey);
    await setCheckbox(addForm, 'auto_add', true);
    await submitForm(addForm, 'Save');
    await expectNotification(page, 'Public key saved');

    const addedRow = rowWithText(page, label);
    await expect(addedRow).toBeVisible();
    const editLink = addedRow.locator('a[href*="action=pubkey_edit"]').first();
    const pubkeyId = await linkParam(editLink, 'pubkey_id');
    await editLink.click();

    const editForm = formByAction(page, 'action=pubkey_edit');
    await editForm.locator('input[name="label"]').fill(editedLabel);
    await setCheckbox(editForm, 'auto_add', false);
    await submitForm(editForm, 'Save');
    await expectNotification(page, 'Public key updated');
    await expect(rowWithText(page, editedLabel)).toBeVisible();

    await actionLink(page, 'pubkey_del', { pubkey_id: pubkeyId }).click();
    await expectNotification(page, 'Public key deleted');
    await expect(page.locator('#content-in')).not.toContainText(editedLabel);

    await logout(page, fixtures.user.username);
  });

  test('user session, known-device, template mail, payment, and metrics pages work', async ({
    page,
  }) => {
    const session = fixtures.user.selfService.userSession;
    const knownDevice = fixtures.user.selfService.knownDevice;
    const metricPrefix = 'webui_self_service';

    await login(page, fixtures.user);

    await page.goto(
      memberActionUrl('user_sessions', fixtures.user.id, {
        list: 1,
        session_id: session.id,
        details: 1,
      }),
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('form[name="user-session-filter"]').first()).toBeVisible();
    await expect(page.locator('input[name="admin"]')).toHaveCount(0);
    await expect(rowWithText(page, session.label)).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('webui-playwright-self-service');

    await actionLink(page, 'user_session_edit', { user_session: session.id }).click();
    const sessionForm = formByAction(page, 'action=user_session_edit');
    await sessionForm.locator('input[name="label"]').fill(session.editedLabel);
    await submitForm(sessionForm, 'Save');
    await expectNotification(page, 'User session updated');
    await expect(rowWithText(page, session.editedLabel)).toBeVisible();

    await actionLink(page, 'user_session_close', { user_session: session.id }).click();
    await expectNotification(page, 'User session closed');
    await expect(actionLink(page, 'user_session_close', { user_session: session.id })).toHaveCount(0);

    await page.goto(memberActionUrl('known_devices', fixtures.user.id, { limit: 5, details: 1 }), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('form[name="known-device-filter"]').first()).toBeVisible();
    await expect(page.locator('#content-in')).toContainText(knownDevice.ip);
    await expect(page.locator('#content-in')).toContainText(knownDevice.ptr);
    await actionLink(page, 'known_device_del', { dev: knownDevice.id }).click();
    await expectNotification(page, 'Known login device deleted');
    await expect(page.locator('#content-in')).not.toContainText(knownDevice.ip);

    await gotoMemberEdit(page, fixtures.user.id);
    await actionLink(page, 'template_recipients').click();
    await expect(page.locator('#content-in')).toContainText('Recipients by e-mail type');
    const templateForm = formByAction(page, 'action=template_recipients');
    await expect(templateForm.locator('textarea[name^="to["]').first()).toBeVisible();
    await submitForm(templateForm, 'Save');
    await expectNotification(page, 'Template e-mails updated');

    await gotoMemberEdit(page, fixtures.user.id);
    await actionLink(page, 'payment_instructions').click();
    await expect(page.locator('#content-in h1')).toContainText('Payment instructions');
    await expect(page.locator('#content-in')).toContainText(
      fixtures.user.selfService.paymentInstructions,
    );

    await page.goto(memberActionUrl('metrics', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Metrics access tokens');
    await actionLink(page, 'metrics_new').click();
    const metricsForm = formByAction(page, 'action=metrics_new');
    await metricsForm.locator('input[name="metric_prefix"]').fill(metricPrefix);
    await submitForm(metricsForm, 'Create');
    await expect(page.locator('#content-in')).toContainText('Metrics access token');
    await expect(page.locator('#content-in')).toContainText(metricPrefix);
    await expect(page.locator('#content-in')).toContainText('/metrics?access_token=');
    const tokenId = new URL(page.url()).searchParams.get('token');

    await page.goto(memberActionUrl('metrics', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(rowWithText(page, metricPrefix)).toBeVisible();
    await actionLink(page, 'metrics_show', { token: tokenId }).click();
    await expect(page.locator('#content-in')).toContainText(metricPrefix);

    await page.goto(memberActionUrl('metrics', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await actionLink(page, 'metrics_delete', { token: tokenId }).click();
    await expectNotification(page, 'Metrics access token deleted');
    await expect(page.locator('#content-in')).not.toContainText(metricPrefix);

    await logout(page, fixtures.user.username);
  });

  test('user passkey list supports visible controls and registration cancellation', async ({
    page,
  }) => {
    const credential = fixtures.user.selfService.webauthnCredential;

    await login(page, fixtures.user);
    await page.goto(memberActionUrl('webauthn_list', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Passkeys');
    await expect(rowWithText(page, credential.label)).toBeVisible();

    const registerForm = page.locator('form[name="webauthn_register"]');
    await expect(registerForm).toBeVisible();
    await submitForm(registerForm, 'Register new passkey');
    await expect(page).toHaveURL(/api\.vpsadmin\.test\/webauthn\/registration\/new/);
    await expect(page.locator('h4')).toContainText('Register passkey into vpsAdmin');
    await page.locator('input[name="cancel"]').click();
    await expect(page).toHaveURL(/page=adminm.*action=webauthn_list/);
    await expectNotification(page, 'Failed to register passkey');
    await expect(page.locator('#perex')).toContainText('Registration cancelled.');

    await actionLink(page, 'webauthn_edit', { cred: credential.id }).click();
    const editForm = formByAction(page, 'action=webauthn_edit');
    await editForm.locator('input[name="label"]').fill(credential.editedLabel);
    await submitForm(editForm, 'Save');
    await expectNotification(page, 'Passkey updated');
    await expect(rowWithText(page, credential.editedLabel)).toBeVisible();

    await actionLink(page, 'webauthn_toggle', { cred: credential.id, toggle: 'disable' }).click();
    await expectNotification(page, 'Passkey disabled');
    await actionLink(page, 'webauthn_toggle', { cred: credential.id, toggle: 'enable' }).click();
    await expectNotification(page, 'Passkey enabled');

    await actionLink(page, 'webauthn_del', { cred: credential.id }).click();
    const deleteForm = formByAction(page, 'action=webauthn_del');
    await setCheckbox(deleteForm, 'confirm', true);
    await submitForm(deleteForm, 'Delete');
    await expectNotification(page, 'Passkey deleted');
    await expect(page.locator('#content-in')).not.toContainText(credential.editedLabel);

    await logout(page, fixtures.user.username);
  });

  test('user TOTP device flow can add, confirm, edit, toggle, and delete', async ({
    page,
  }) => {
    const label = 'Webui Self-Service TOTP';
    const editedLabel = 'Webui Self-Service TOTP Edited';

    await login(page, fixtures.user);
    await page.goto(memberActionUrl('totp_devices', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('TOTP devices');

    await actionLink(page, 'totp_device_add').click();
    const addForm = formByAction(page, 'action=totp_device_add');
    await addForm.locator('input[name="label"]').fill(label);
    await submitForm(addForm, 'Continue');

    await expect(page).toHaveURL(/action=totp_device_confirm/);
    const deviceId = new URL(page.url()).searchParams.get('dev');
    const secret = await detailValue(page, 'Secret key');
    await waitForStableTotpWindow(page);
    const confirmForm = formByAction(page, 'action=totp_device_confirm');
    await confirmForm.locator('input[name="code"]').fill(totpCode(secret));
    await submitForm(confirmForm, 'Enable the device for two-factor authentication');
    await expectNotification(page, 'The TOTP device was configured');
    await expect(page.locator('#content-in')).toContainText('Recovery code');

    await page.goto(memberActionUrl('totp_devices', fixtures.user.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(rowWithText(page, label)).toBeVisible();

    await actionLink(page, 'totp_device_edit', { dev: deviceId }).click();
    const editForm = formByAction(page, 'action=totp_device_edit');
    await editForm.locator('input[name="label"]').fill(editedLabel);
    await submitForm(editForm, 'Save');
    await expectNotification(page, 'TOTP device updated');
    await expect(rowWithText(page, editedLabel)).toBeVisible();

    await actionLink(page, 'totp_device_toggle', { dev: deviceId, toggle: 'disable' }).click();
    await expectNotification(page, 'TOTP device disabled');
    await actionLink(page, 'totp_device_toggle', { dev: deviceId, toggle: 'enable' }).click();
    await expectNotification(page, 'TOTP device enabled');

    await actionLink(page, 'totp_device_del', { dev: deviceId }).click();
    const deleteForm = formByAction(page, 'action=totp_device_del');
    await setCheckbox(deleteForm, 'confirm', true);
    await submitForm(deleteForm, 'Delete');
    await expectNotification(page, 'TOTP device deleted');
    await expect(page.locator('#content-in')).not.toContainText(editedLabel);
    await submitMfaEnabled(page, fixtures.user.id, false);

    await logout(page, fixtures.user.username);
  });

  test('user cannot access admin-only member and payment actions', async ({ page }) => {
    await login(page, fixtures.user);

    await gotoMemberList(page);
    await expect(actionLink(page, 'new')).toHaveCount(0);
    await expect(actionLink(page, 'incoming_payments')).toHaveCount(0);
    await expect(actionLink(page, 'payments_history')).toHaveCount(0);
    await expect(actionLink(page, 'payments_overview')).toHaveCount(0);
    await expect(actionLink(page, 'estimate_income')).toHaveCount(0);

    await expectAdminOnlyActionHidden(
      page,
      '/?page=adminm&section=members&action=new',
      'Add a member',
      'input[name="m_nick"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('delete', fixtures.user.id),
      'Delete member',
      'form[action*="action=delete2"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('payset', fixtures.user.id),
      'User payments',
      'form[action*="action=payset2"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('incoming_payments', fixtures.user.id),
      'Incoming payments',
      'form[action*="action=incoming_payments"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('payments_history', fixtures.user.id),
      'Payment history',
      'form[action*="action=payments_history"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('payments_overview', fixtures.user.id),
      'Payments overview',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('estimate_income', fixtures.user.id),
      'Estimate income',
      'input[name="y"]',
    );
    await expectAdminOnlyActionHidden(
      page,
      memberActionUrl('resource_packages_add', fixtures.user.id),
      'Add cluster resource package',
      'form[action*="action=resource_packages_add"]',
    );

    await page.goto(memberActionUrl('cluster_resources', fixtures.users.secondary.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#perex')).toContainText(/Access denied|Action failed/);

    await logout(page, fixtures.user.username);
  });
});
