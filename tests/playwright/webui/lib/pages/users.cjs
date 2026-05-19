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

function rowWithText(page, text) {
  return page.locator('table.table-style01 tr', { hasText: text }).first();
}

function memberListFilterForm(page) {
  return page.locator('form[name="user-filter"]', {
    has: page.locator('input[name="login"]'),
  }).first();
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

async function submitMemberListFilters(page, filters = {}) {
  await page.goto('/?page=adminm&action=list', { waitUntil: 'domcontentloaded' });

  const form = memberListFilterForm(page);
  await expect(form).toBeVisible();

  if (filters.limit !== undefined) {
    await form.locator('input[name="limit"]').fill(String(filters.limit));
  }
  if (filters.fromId !== undefined) {
    await form.locator('input[name="from_id"]').fill(String(filters.fromId));
  }
  if (filters.login !== undefined) {
    await form.locator('input[name="login"]').fill(filters.login);
  }
  if (filters.email !== undefined) {
    await form.locator('input[name="email"]').fill(filters.email);
  }
  if (filters.level !== undefined) {
    await form.locator('input[name="level"]').fill(String(filters.level));
  }
  if (filters.objectState !== undefined) {
    await form.locator('select[name="object_state"]').selectOption(filters.objectState);
  }

  await Promise.all([
    page.waitForURL(/page=adminm.*action=list/, { waitUntil: 'domcontentloaded' }),
    submitForm(form, 'Show'),
  ]);
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
  const currentPasswordInput = form.locator('input[name="password"]');
  if ((await currentPasswordInput.count()) > 0 && currentPassword !== null) {
    await currentPasswordInput.fill(currentPassword);
  }
  await form.locator('input[name="new_password"]').fill(newPassword);
  await form.locator('input[name="new_password2"]').fill(newPassword);
  await setCheckboxIfPresent(form, 'logout_sessions', false);
  await submitForm(form, 'Set');
  await expectNotification(page, 'Password set');
}

async function createAdminUser(page, user) {
  await page.goto('/?page=adminm&action=new', {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('Add a member');

  const form = formByAction(page, 'action=new2');
  await expect(form).toBeVisible();
  await form.locator('input[name="m_nick"]').fill(user.login);
  await form.locator('select[name="m_level"]').selectOption(String(user.level || 2));
  await form.locator('input[name="m_pass"]').fill(user.password);
  await form.locator('input[name="m_pass2"]').fill(user.password);
  await form.locator('input[name="m_name"]').fill(user.fullName);
  await form.locator('input[name="m_mail"]').fill(user.email);
  await form.locator('input[name="m_address"]').fill(user.address || 'Webui Admin Address');

  const monthlyPayment = form.locator('input[name="m_monthly_payment"]');
  if ((await monthlyPayment.count()) > 0) {
    await monthlyPayment.fill(String(user.monthlyPayment || 100));
  }

  await setCheckboxIfPresent(form, 'm_mailer_enable', false);
  await submitForm(form, 'Add');
  await expectNotification(page, 'User created');
  await expect(page).toHaveURL(/page=adminm.*action=edit.*id=/);

  return new URL(page.url()).searchParams.get('id');
}

async function deleteAdminUser(page, userId, objectState = 'hard_delete') {
  await page.goto(memberActionUrl('delete', userId), { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Delete member');

  const form = formByAction(page, 'action=delete2');
  await expect(form).toBeVisible();
  await form.locator('select[name="object_state"]').selectOption(objectState);
  await submitForm(form, 'Delete');

  await expect(page.locator('#perex')).toContainText('Are you sure');
  const yesLink = page.locator('#perex a[href*="action=delete3"]', { hasText: /^YES$/ }).first();
  await expect(yesLink).toHaveAttribute('href', /object_state=/);
  await yesLink.click();
  await expectNotification(page, 'User deleted');
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
  createAdminUser,
  deleteAdminUser,
  gotoMemberEdit,
  gotoMemberList,
  linkParam,
  memberListFilterForm,
  memberActionUrl,
  memberRow,
  rowWithText,
  setCheckbox,
  setCheckboxIfPresent,
  submitAuthSettings,
  submitCurrentMemberSettings,
  submitMemberListFilters,
  submitMfaEnabled,
  submitSessionControl,
};
