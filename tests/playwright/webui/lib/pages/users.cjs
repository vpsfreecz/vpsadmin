const { expect } = require('@playwright/test');

const {
  expectNotification,
  formByAction,
  submitForm,
} = require('./webui.cjs');

function memberActionUrl(action, userId, extra = {}) {
  const params = new URLSearchParams({
    page: 'adminm',
    action,
    id: String(userId),
    ...Object.fromEntries(
      Object.entries(extra).map(([key, value]) => [key, String(value)]),
    ),
  });

  return `/?${params.toString()}`;
}

async function gotoMemberList(page) {
  await page.goto('/?page=adminm', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('Manage members');
}

async function gotoMemberEdit(page, userId) {
  await page.goto(memberActionUrl('edit', userId), { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('Manage members');
}

function memberRow(page, userId) {
  return page.locator('table.table-style01 tr', {
    has: page.locator(`a[href*="action=edit"][href*="id=${userId}"]`),
  }).first();
}

function actionLink(page, action, params = {}) {
  let selector = `a[href*="action=${action}"]`;

  for (const [key, value] of Object.entries(params)) {
    selector += `[href*="${key}=${value}"]`;
  }

  return page.locator(selector).first();
}

async function setCheckbox(form, name, enabled) {
  const checkbox = form.locator(`input[name="${name}"]`);
  await expect(checkbox).toBeVisible();

  if (enabled) {
    await checkbox.check();
    await expect(checkbox).toBeChecked();
  } else {
    await checkbox.uncheck();
    await expect(checkbox).not.toBeChecked();
  }
}

async function setCheckboxIfPresent(form, name, enabled) {
  const checkbox = form.locator(`input[name="${name}"]`);

  if ((await checkbox.count()) === 0) {
    return false;
  }

  await setCheckbox(form, name, enabled);
  return true;
}

async function submitCurrentMemberSettings(page, userId) {
  await gotoMemberEdit(page, userId);

  const form = formByAction(page, 'action=edit_member');
  await expect(form).toBeVisible();
  await submitForm(form, 'Save');
  await expectNotification(page, 'User updated');
}

async function submitAuthSettings(page, userId, settings) {
  await gotoMemberEdit(page, userId);

  const form = formByAction(page, 'action=auth_settings');
  await expect(form).toBeVisible();

  for (const [name, enabled] of Object.entries(settings)) {
    await setCheckbox(form, name, enabled);
  }

  await submitForm(form, 'Save');
  await expectNotification(page, 'Authentication settings updated');
}

async function submitSessionControl(page, userId, settings) {
  await gotoMemberEdit(page, userId);

  const form = formByAction(page, 'action=session_control');
  await expect(form).toBeVisible();

  if (settings.enableSingleSignOn !== undefined) {
    await setCheckbox(form, 'enable_single_sign_on', settings.enableSingleSignOn);
  }

  if (settings.preferredSessionLength !== undefined) {
    await form
      .locator('input[name="preferred_session_length"]')
      .fill(String(settings.preferredSessionLength));
  }

  if (settings.preferredLogoutAll !== undefined) {
    await setCheckbox(form, 'preferred_logout_all', settings.preferredLogoutAll);
  }

  await submitForm(form, 'Save');
  await expectNotification(page, 'Session control updated');
}

async function submitMfaEnabled(page, userId, enabled) {
  await gotoMemberEdit(page, userId);

  const form = formByAction(page, 'action=edit_mfa');
  await expect(form).toBeVisible();
  await setCheckbox(form, 'enable_multi_factor_auth', enabled);
  await submitForm(form, 'Save');
  await expectNotification(
    page,
    enabled ? 'Multi-factor authentication enabled' : 'Multi-factor authentication disabled',
  );
}

async function changePassword(page, userId, currentPassword, newPassword) {
  await gotoMemberEdit(page, userId);

  const form = formByAction(page, 'action=passwd');
  await expect(form).toBeVisible();
  await form.locator('input[name="password"]').fill(currentPassword);
  await form.locator('input[name="new_password"]').fill(newPassword);
  await form.locator('input[name="new_password2"]').fill(newPassword);
  await setCheckboxIfPresent(form, 'logout_sessions', false);
  await submitForm(form, 'Set');
  await expectNotification(page, 'Password set');
}

async function linkParam(locator, param) {
  const href = await locator.getAttribute('href');

  if (!href) {
    throw new Error(`Link has no href while reading ${param}`);
  }

  return new URL(href, 'http://webui.vpsadmin.test/').searchParams.get(param);
}

module.exports = {
  actionLink,
  changePassword,
  gotoMemberEdit,
  gotoMemberList,
  linkParam,
  memberActionUrl,
  memberRow,
  setCheckbox,
  setCheckboxIfPresent,
  submitAuthSettings,
  submitCurrentMemberSettings,
  submitMfaEnabled,
  submitSessionControl,
};
