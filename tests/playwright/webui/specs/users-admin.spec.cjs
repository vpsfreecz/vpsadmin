const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  actionLink,
  changePassword,
  createAdminUser,
  deleteAdminUser,
  gotoMemberEdit,
  linkParam,
  memberListFilterForm,
  memberActionUrl,
  memberRow,
  rowWithText,
  setCheckbox,
  setCheckboxIfPresent,
  submitAuthSettings,
  submitMemberListFilters,
  submitMfaEnabled,
  submitSessionControl,
} = require('../lib/pages/users.cjs');

const fixtures = readFixtures();
const managed = fixtures.adminMembers && fixtures.adminMembers.managed;
const adminPublicKey =
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICdl1OmUwRKSkYjismjOiW46qAeMkIFwYfKNNSUaIbC6 webui-admin-managed@test';
const languageFlag = (page, locale) =>
  page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`);

async function switchLanguage(page, locale) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
    languageFlag(page, locale).click(),
  ]);
}

function requireManagedFixture() {
  if (!managed || !managed.id || !managed.username) {
    throw new Error('users-admin requires fixtures.adminMembers.managed');
  }

  return managed;
}

function uniqueLogin(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function futureDate(days) {
  const date = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  const pad = (value) => String(value).padStart(2, '0');

  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join('-');
}

function dataRows(page) {
  return page.locator('table.table-style01 tr', {
    has: page.locator('a[href*="action=edit"][href*="id="]'),
  });
}

function scopedActionLink(scope, action, params = {}) {
  let selector = `a[href*="action=${action}"]`;

  for (const [key, value] of Object.entries(params)) {
    selector += `[href*="${key}=${value}"]`;
  }

  return scope.locator(selector).first();
}

function tableContaining(page, ...texts) {
  let table = page.locator('table.table-style01');

  for (const text of texts) {
    table = table.filter({ hasText: text });
  }

  return table.first();
}

function tableAfterHeading(page, heading) {
  return page
    .locator('h2', { hasText: heading })
    .first()
    .locator('xpath=following::table[1]');
}

async function submitRequestProcess(page, request, action) {
  await page.goto(
    `/?page=adminm&action=request_details&id=${request.id}&type=${request.type}`,
    { waitUntil: 'domcontentloaded' },
  );
  await expect(page.locator('#content-in')).toContainText('Request for approval details');
  await expect(page.locator('#content-in')).toContainText(request.reason);

  const form = formByAction(page, 'action=request_process');
  await expect(form).toBeVisible();
  await form.locator('select[name="action"]').selectOption(action);

  const reason = form.locator('[name="reason"]').first();
  if ((await reason.count()) > 0) {
    await reason.fill(`Webui admin ${action} coverage`);
  }

  await submitForm(form, 'Close request');
  await expectNotification(
    page,
    {
      approve: 'Request approved',
      deny: 'Request denied',
      ignore: 'Request ignored',
    }[action],
  );
}

test.describe.serial('admin member and user management browser coverage', () => {
  test('admin user list filters and isolated create/edit/delete flow work', async ({ page }) => {
    const target = requireManagedFixture();
    const loginName = uniqueLogin('webui-admin-created');
    const isolatedUser = {
      login: loginName,
      password: `webuiCreatedPassword${Date.now().toString(36)}`,
      fullName: 'Webui Admin Created User',
      email: `${loginName}@example.test`,
      address: 'Webui Admin Created Address',
      level: 2,
      monthlyPayment: 100,
    };

    await login(page, fixtures.admin);

    await submitMemberListFilters(page, {
      limit: 1,
      fromId: target.id - 1,
      login: target.username,
      email: target.email,
      level: 2,
      objectState: 'active',
    });

    const filterForm = memberListFilterForm(page);
    await expect(filterForm.locator('input[name="limit"]')).toHaveValue('1');
    await expect(filterForm.locator('input[name="from_id"]')).toHaveValue(String(target.id - 1));
    await expect(filterForm.locator('input[name="login"]')).toHaveValue(target.username);
    await expect(filterForm.locator('input[name="email"]')).toHaveValue(target.email);
    await expect(filterForm.locator('input[name="level"]')).toHaveValue('2');
    await expect(filterForm.locator('select[name="object_state"]')).toHaveValue('active');
    await expect(dataRows(page)).toHaveCount(1);
    await expect(memberRow(page, target.id)).toContainText(target.username);

    const createdUserId = await createAdminUser(page, isolatedUser);
    await gotoMemberEdit(page, createdUserId);

    const editForm = formByAction(page, 'action=edit_member');
    await editForm.locator('input[name="m_nick"]').fill(isolatedUser.login);
    await editForm.locator('select[name="m_level"]').selectOption('2');
    await editForm.locator('textarea[name="m_info"]').fill('Webui admin edit_member coverage');
    await setCheckboxIfPresent(editForm, 'm_mailer_enable', false);
    await setCheckboxIfPresent(editForm, 'm_password_reset', false);
    await setCheckboxIfPresent(editForm, 'm_lockout', false);
    const monthlyPayment = editForm.locator('input[name="m_monthly_payment"]');
    if ((await monthlyPayment.count()) > 0) {
      await monthlyPayment.fill('100');
    }
    await submitForm(editForm, 'Save');
    await expectNotification(page, 'User updated');

    await deleteAdminUser(page, createdUserId, 'hard_delete');
    await logout(page, fixtures.admin.username);
  });

  test('admin can change another user password and auth/session settings', async ({ page }) => {
    const target = requireManagedFixture();
    const temporaryPassword = `webuiAdminManaged${Date.now().toString(36)}`;
    let activePassword = target.password;

    await login(page, fixtures.admin);

    try {
      await changePassword(page, target.id, null, temporaryPassword);
      activePassword = temporaryPassword;
      await changePassword(page, target.id, null, target.password);
      activePassword = target.password;
    } finally {
      if (activePassword !== target.password) {
        await changePassword(page, target.id, null, target.password);
      }
    }

    await submitAuthSettings(page, target.id, {
      enable_basic_auth: false,
      enable_token_auth: false,
      enable_new_login_notification: false,
    });
    await submitAuthSettings(page, target.id, {
      enable_basic_auth: true,
      enable_token_auth: true,
      enable_new_login_notification: true,
    });
    await submitSessionControl(page, target.id, {
      enableSingleSignOn: false,
      preferredSessionLength: 5,
      preferredLogoutAll: true,
    });
    await submitSessionControl(page, target.id, {
      enableSingleSignOn: true,
      preferredSessionLength: 20,
      preferredLogoutAll: false,
    });
    await submitMfaEnabled(page, target.id, true);
    await submitMfaEnabled(page, target.id, false);

    await logout(page, fixtures.admin.username);
  });

  test('admin manages another user public keys, sessions, and metrics tokens', async ({ page }) => {
    const target = requireManagedFixture();
    const keyLabel = 'Webui Admin Managed Key Added';
    const editedKeyLabel = 'Webui Admin Managed Key Added Edited';
    const session = target.userSession;
    const metricPrefix = 'webui_admin_managed';

    await login(page, fixtures.admin);

    await page.goto(memberActionUrl('pubkeys', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Public keys');
    await expect(page.locator('#content-in')).toContainText(target.publicKey.label);

    await actionLink(page, 'pubkey_add').click();
    const addKeyForm = formByAction(page, 'action=pubkey_add');
    await addKeyForm.locator('input[name="label"]').fill(keyLabel);
    await addKeyForm.locator('textarea[name="key"]').fill(adminPublicKey);
    await setCheckbox(addKeyForm, 'auto_add', true);
    await submitForm(addKeyForm, 'Save');
    await expectNotification(page, 'Public key saved');

    const addedKeyRow = rowWithText(page, keyLabel);
    await expect(addedKeyRow).toBeVisible();
    const editKeyLink = addedKeyRow.locator('a[href*="action=pubkey_edit"]').first();
    const pubkeyId = await linkParam(editKeyLink, 'pubkey_id');
    await editKeyLink.click();

    const editKeyForm = formByAction(page, 'action=pubkey_edit');
    await editKeyForm.locator('input[name="label"]').fill(editedKeyLabel);
    await setCheckbox(editKeyForm, 'auto_add', false);
    await submitForm(editKeyForm, 'Save');
    await expectNotification(page, 'Public key updated');
    await expect(rowWithText(page, editedKeyLabel)).toBeVisible();
    await actionLink(page, 'pubkey_del', { pubkey_id: pubkeyId }).click();
    await expectNotification(page, 'Public key deleted');

    await page.goto(
      memberActionUrl('user_sessions', target.id, {
        list: 1,
        session_id: session.id,
        details: 1,
      }),
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('form[name="user-session-filter"]').first()).toBeVisible();
    await expect(page.locator('input[name="admin"]')).toBeVisible();
    await expect(rowWithText(page, session.label)).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('webui-playwright-admin-managed');

    await actionLink(page, 'user_session_edit', { user_session: session.id }).click();
    const sessionForm = formByAction(page, 'action=user_session_edit');
    await sessionForm.locator('input[name="label"]').fill(session.editedLabel);
    await submitForm(sessionForm, 'Save');
    await expectNotification(page, 'User session updated');
    await expect(rowWithText(page, session.editedLabel)).toBeVisible();

    await actionLink(page, 'user_session_close', { user_session: session.id }).click();
    await expectNotification(page, 'User session closed');

    await page.goto(memberActionUrl('metrics', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Metrics access tokens');
    await actionLink(page, 'metrics_new').click();
    const metricsForm = formByAction(page, 'action=metrics_new');
    await metricsForm.locator('input[name="metric_prefix"]').fill(metricPrefix);
    await submitForm(metricsForm, 'Create');
    await expect(page.locator('#content-in')).toContainText('Metrics access token');
    await expect(page.locator('#content-in')).toContainText(metricPrefix);
    const tokenId = new URL(page.url()).searchParams.get('token');

    await page.goto(memberActionUrl('metrics', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(rowWithText(page, metricPrefix)).toBeVisible();
    await actionLink(page, 'metrics_show', { token: tokenId }).click();
    await expect(page.locator('#content-in')).toContainText('/metrics?access_token=');
    await expect(page.locator('#content-in')).toContainText(metricPrefix);

    await page.goto(memberActionUrl('metrics', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await actionLink(page, 'metrics_delete', { token: tokenId }).click();
    await expectNotification(page, 'Metrics access token deleted');

    await logout(page, fixtures.admin.username);
  });

  test('admin resource packages, cluster resources, and env config work', async ({
    page,
  }) => {
    const target = requireManagedFixture();
    const pkg = target.resourcePackage;

    await login(page, fixtures.admin);

    await page.goto(memberActionUrl('resource_packages', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Cluster resource packages');
    await actionLink(page, 'resource_packages_add').click();

    const addPackageForm = formByAction(page, 'action=resource_packages_add');
    await addPackageForm.locator('select[name="environment"]').selectOption(
      String(fixtures.environment.id),
    );
    await addPackageForm.locator('select[name="cluster_resource_package"]').selectOption(
      String(pkg.id),
    );
    await addPackageForm.locator('[name="comment"]').fill('Webui admin package add');
    await setCheckboxIfPresent(addPackageForm, 'from_personal', false);
    await submitForm(addPackageForm, 'Add');
    await expectNotification(page, 'Package added');
    const addedPackageTable = tableContaining(page, pkg.label, 'Webui admin package add');
    await expect(addedPackageTable).toBeVisible();

    const editPackageLink = scopedActionLink(
      addedPackageTable,
      'resource_packages_edit',
      { id: target.id },
    );
    const userPackageId = await linkParam(editPackageLink, 'pkg');
    await editPackageLink.click();
    const editPackageForm = formByAction(page, 'action=resource_packages_edit');
    await editPackageForm.locator('[name="comment"]').fill('Webui admin package edited');
    await submitForm(editPackageForm, 'Save');
    await expectNotification(page, 'Package updated');
    const editedPackageTable = tableContaining(page, pkg.label, 'Webui admin package edited');
    await expect(editedPackageTable).toBeVisible();

    await scopedActionLink(
      editedPackageTable,
      'resource_packages_delete',
      { pkg: userPackageId },
    ).click();
    const deletePackageForm = formByAction(page, 'action=resource_packages_delete');
    await setCheckbox(deletePackageForm, 'confirm', true);
    await submitForm(deletePackageForm, 'Remove');
    await expectNotification(page, 'Package removed');

    await page.goto(memberActionUrl('cluster_resources', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Cluster resources');
    await expect(page.locator('#content-in')).toContainText(fixtures.environment.label);
    await expect(page.locator('#content-in')).toContainText('CPU');

    await page.goto(memberActionUrl('env_cfg', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Environment configs');
    await expect(page.locator('#content-in')).toContainText(fixtures.environment.label);
    await page.goto(
      memberActionUrl('env_cfg_edit', target.id, {
        cfg: target.environmentConfig.id,
      }),
      { waitUntil: 'domcontentloaded' },
    );
    const envForm = formByAction(page, 'action=env_cfg_edit');
    await setCheckbox(envForm, 'can_create_vps', true);
    await setCheckbox(envForm, 'can_destroy_vps', true);
    await envForm.locator('input[name="vps_lifetime"]').fill('0');
    await envForm.locator('input[name="max_vps_count"]').fill('17');
    await submitForm(envForm, 'Customize');
    await expectNotification(page, 'Settings customized');

    await page.goto(
      memberActionUrl('env_cfg_edit', target.id, {
        cfg: target.environmentConfig.id,
      }),
      { waitUntil: 'domcontentloaded' },
    );
    const resetForm = formByAction(page, 'action=env_cfg_reset');
    await expect(resetForm).toBeVisible();
    await submitForm(resetForm, 'Reset');
    await expectNotification(page, 'Settings reset to default');

    await logout(page, fixtures.admin.username);
  });

  test('admin payment and finance pages submit filters and state changes', async ({ page }) => {
    const target = requireManagedFixture();
    const incoming = target.incomingPayment;

    await login(page, fixtures.admin);

    await page.goto(memberActionUrl('payset', target.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('User payments');
    await expect(page.locator('#content-in')).toContainText(target.username);

    const paidUntilForm = page
      .locator('form[action*="action=payset2"]', {
        has: page.locator('input[name="paid_until"]'),
      })
      .first();
    await paidUntilForm.locator('input[name="paid_until"]').fill(futureDate(30));
    await submitForm(paidUntilForm, 'Save');
    await expectNotification(page, 'Paid until date set');

    const amountForm = page
      .locator('form[action*="action=payset2"]', {
        has: page.locator('input[name="amount"]'),
      })
      .first();
    await amountForm.locator('input[name="amount"]').fill(String(target.monthlyPayment));
    await submitForm(amountForm, 'Save');
    await expectNotification(page, 'Payment accepted');

    await page.goto('/?page=adminm&action=incoming_payments', {
      waitUntil: 'domcontentloaded',
    });
    const incomingFilter = formByAction(page, 'action=incoming_payments');
    await incomingFilter.locator('input[name="limit"]').fill('10');
    await incomingFilter.locator('input[name="from_id"]').fill(String(incoming.id + 1));
    await incomingFilter.locator('select[name="state"]').selectOption(incoming.state);
    await submitForm(incomingFilter, 'Show');
    await expect(page.locator('#content-in')).toContainText('Incoming payments');
    await expect(rowWithText(page, 'webui admin managed payment')).toBeVisible();

    await page.goto(memberActionUrl('incoming_payment', incoming.id), {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(`Incoming payment #${incoming.id}`);
    await expect(page.locator('#content-in')).toContainText('webui admin managed payment');
    const stateForm = formByAction(page, 'action=incoming_payment_state');
    await stateForm.locator('select[name="state"]').selectOption('ignored');
    await submitForm(stateForm, 'Set state');
    await expectNotification(page, 'State changed');

    const assignForm = formByAction(page, 'action=incoming_payment_assign');
    await assignForm.locator('input[name="user"]').fill(String(target.id));
    await submitForm(assignForm, 'Assign');
    await expectNotification(page, 'Payment assigned');
    await expect(page.locator('#content-in')).toContainText('User payments');

    await page.goto(
      `/?page=adminm&action=payments_history&limit=10&user=${target.id}&accounted_by=${fixtures.admin.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Payment history');
    await expect(formByAction(page, 'action=payments_history')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText(target.username);

    await page.goto('/?page=adminm&action=payments_overview', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Payments overview');
    await expect(page.locator('#content-in')).toContainText('Total monthly income');

    const now = new Date();
    await page.goto(
      `/?page=adminm&action=estimate_income&y=${now.getFullYear()}&m=${now.getMonth() + 1}&s=all_until&d=1`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Estimate income');
    await expect(page.locator('#content-in')).toContainText('Estimated income');

    try {
      await switchLanguage(page, 'cs_CZ.utf8');

      await page.goto(memberActionUrl('payset', target.id), {
        waitUntil: 'domcontentloaded',
      });
      const payset = page.locator('#content-in');
      await expect(payset).toContainText('Platby uživatele');
      await expect(payset).toContainText('Přezdívka:');
      await expect(payset).toContainText('Částka:');
      await expect(payset).toContainText('Přehled plateb');
      await expect(tableAfterHeading(page, 'Přehled plateb').locator('th')).toHaveText([
        'PŘIJATO',
        'ZAÚČTOVAL',
        'ČÁSTKA',
        'OD',
        'DO',
        'PLATBA',
      ]);

      await page.goto('/?page=adminm&action=incoming_payments', {
        waitUntil: 'domcontentloaded',
      });
      const incomingTable = tableContaining(page, 'webui admin managed payment');
      await expect(incomingTable.locator('th')).toHaveText([
        'DATUM',
        'ČÁSTKA',
        'STAV',
        'PLÁTCE',
        'ZPRÁVA',
        'VS',
        '',
      ]);
      await expect(
        formByAction(page, 'action=incoming_payments').locator('select[name="state"] option'),
      ).toHaveText(['ve frontě', 'bez shody', 'zpracováno', 'ignorováno']);
      await expect(rowWithText(page, 'webui admin managed payment')).toContainText('zpracováno');

      await page.goto(memberActionUrl('incoming_payment', incoming.id), {
        waitUntil: 'domcontentloaded',
      });
      const incomingDetails = page.locator('#content-in');
      await expect(incomingDetails).toContainText('ID transakce:');
      await expect(incomingDetails).toContainText('Přijato:');
      await expect(incomingDetails).toContainText('Částka:');

      await page.goto(
        `/?page=adminm&action=payments_history&limit=10&user=${target.id}&accounted_by=${fixtures.admin.id}`,
        { waitUntil: 'domcontentloaded' },
      );
      const historyTable = tableContaining(page, target.username);
      await expect(historyTable.locator('th')).toHaveText([
        'PŘIJATO',
        'UŽIVATEL',
        'ZAÚČTOVAL',
        'ČÁSTKA',
        'OD',
        'DO',
        'MĚSÍCE',
      ]);
    } finally {
      await switchLanguage(page, 'en_US.utf8');
    }

    await logout(page, fixtures.admin.username);
  });

  test('admin approval request list, details, approve, deny, and ignore work', async ({ page }) => {
    const target = requireManagedFixture();
    const requests = target.approvalRequests;

    await login(page, fixtures.admin);

    const hardDeleted = requests.hardDeletedDenied;
    await page.goto(
      '/?page=adminm&action=approval_requests&type=change&state=denied&limit=10',
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText(hardDeleted.reason);
    const hardDeletedRow = rowWithText(page, hardDeleted.reason);
    const hardDeletedUser = hardDeletedRow
      .locator('dt')
      .filter({ hasText: /^User:$/ })
      .locator('xpath=following-sibling::dd[1]');
    await expect(hardDeletedUser).toHaveText(String(hardDeleted.userId));
    await expect(
      page.locator(`a[href*="action=request_process"][href*="id=${hardDeleted.id}"]`),
    ).toHaveCount(0);

    await page.goto(
      `/?page=adminm&action=request_details&id=${hardDeleted.id}&type=${hardDeleted.type}`,
      { waitUntil: 'domcontentloaded' },
    );
    const hardDeletedDetails = page.locator('#content-in');
    await expect(hardDeletedDetails).toContainText('Request for approval details');
    await expect(hardDeletedDetails).toContainText(hardDeleted.reason);
    await expect(hardDeletedDetails).toContainText(hardDeleted.fullName);
    await expect(hardDeletedDetails).toContainText(hardDeleted.email);
    await expect(hardDeletedDetails).toContainText(hardDeleted.address);
    const applicant = hardDeletedDetails
      .locator('td')
      .filter({ hasText: /^Applicant:$/ })
      .locator('xpath=following-sibling::td[1]');
    await expect(applicant).toHaveText(String(hardDeleted.userId));
    await expect(formByAction(page, 'action=request_process')).toHaveCount(0);

    await page.goto(
      `/?page=adminm&action=approval_requests&type=change&state=awaiting&limit=10&user=${target.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Requests for approval');
    const requestFilter = formByAction(page, 'action=approval_requests');
    await expect(requestFilter.locator('input[name="limit"]')).toHaveValue('10');
    await expect(requestFilter.locator('select[name="type"]')).toHaveValue('change');
    await expect(requestFilter.locator('select[name="state"]')).toHaveValue('awaiting');
    await expect(requestFilter.locator('input[name="user"]')).toHaveValue(String(target.id));
    await expect(page.locator('#content-in')).toContainText(requests.approve.reason);
    await expect(page.locator('#content-in')).toContainText(requests.deny.reason);
    await expect(page.locator('#content-in')).toContainText(requests.ignore.reason);

    await submitRequestProcess(page, requests.approve, 'approve');
    await submitRequestProcess(page, requests.deny, 'deny');
    await submitRequestProcess(page, requests.ignore, 'ignore');

    await logout(page, fixtures.admin.username);
  });
});
