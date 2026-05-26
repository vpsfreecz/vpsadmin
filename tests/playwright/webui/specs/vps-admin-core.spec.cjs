const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  expectNotification,
  formByAction,
  gotoVpsDetail,
  submitForm,
  waitForQueryParams,
  waitForVpsStatus,
  waitForVpsTransactionsSettled,
} = require('../lib/pages/webui.cjs');
const {
  createAdminVps,
  disableAdminNetwork,
  enableAdminNetwork,
  runDetailAction,
  setAdminAutostartPriority,
  setAdminMapMode,
  setAdminObjectState,
  submitAdminNetworkInterface,
  submitAdminResources,
  vpsListRow,
} = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();
const smallResources = {
  diskspace: 1024,
};

function hostname(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function futureDateTime(days) {
  const date = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  const pad = (value) => String(value).padStart(2, '0');

  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join('-') + ' 00:00:00';
}

function adminCreateOptions(options = {}) {
  return {
    nodeId: fixtures.node.id,
    userId: fixtures.user.id,
    ...options,
    resources: {
      ...smallResources,
      ...(options.resources || {}),
    },
  };
}

function listDataRows(page) {
  return page.locator('table.table-style01 tr', {
    has: page.locator('a[href*="action=info&veid="]'),
  });
}

async function submitAdminListFilters(page, filters = {}) {
  await page.goto('/?page=adminvps&action=list', { waitUntil: 'domcontentloaded' });

  const form = page.locator('form[name="vps-filter"]', {
    has: page.locator('input[name="user"]'),
  });
  await expect(form).toBeVisible();

  if (filters.limit !== undefined) {
    await form.locator('input[name="limit"]').fill(String(filters.limit));
  }
  if (filters.fromId !== undefined) {
    await form.locator('input[name="from_id"]').fill(String(filters.fromId));
  }
  if (filters.userId !== undefined) {
    await form.locator('input[name="user"]').fill(String(filters.userId));
  }
  if (filters.nodeId !== undefined) {
    await form.locator('select[name="node"]').selectOption(String(filters.nodeId));
  }
  if (filters.locationId !== undefined) {
    await form.locator('select[name="location"]').selectOption(String(filters.locationId));
  }
  if (filters.environmentId !== undefined) {
    await form.locator('select[name="environment"]').selectOption(String(filters.environmentId));
  }
  if (filters.objectState !== undefined) {
    await form.locator('select[name="object_state"]').selectOption(String(filters.objectState));
  }
  if (filters.userNamespaceMapId !== undefined) {
    await form.locator('input[name="user_namespace_map"]').fill(String(filters.userNamespaceMapId));
  }

  await submitForm(form, 'Show');
  await expect(page).toHaveURL(/page=adminvps.*action=list/);
}

async function expectAdminRowActionLinks(page, vpsId) {
  const row = vpsListRow(page, vpsId);

  await expect(row.locator(`a[href*="run=restart"][href*="veid=${vpsId}"]`)).toBeVisible();
  await expect(row.locator(`a[href*="run=stop"][href*="veid=${vpsId}"]`)).toBeVisible();
  await expect(row.locator(`a[href*="page=cluster"][href*="type=vps"][href*="obj_id=${vpsId}"]`)).toBeVisible();
  await expect(row.locator(`a[href*="action=migrate-step-1"][href*="veid=${vpsId}"]`)).toBeVisible();
  await expect(row.locator(`a[href*="action=delete"][href*="veid=${vpsId}"]`)).toBeVisible();
}

async function openAdminVpsListAround(page, vpsId, filters = {}) {
  await submitAdminListFilters(page, {
    fromId: vpsId - 1,
    limit: 1,
    userId: fixtures.user.id,
    ...filters,
  });
}

async function withoutDialogs(page, callback) {
  const dialogs = [];
  const handler = async (dialog) => {
    dialogs.push(`${dialog.type()}: ${dialog.message()}`);
    await dialog.accept();
  };

  page.on('dialog', handler);
  try {
    await callback();
    await page.waitForTimeout(250);
  } finally {
    page.off('dialog', handler);
  }

  expect(dialogs).toEqual([]);
}

async function runFilteredListAction(page, vpsId, action, expectedNotification, expectedStatus = null) {
  await openAdminVpsListAround(page, vpsId);

  await withoutDialogs(page, async () => {
    await vpsListRow(page, vpsId)
      .locator(`a[href*="run=${action}"][href*="veid=${vpsId}"]`)
      .first()
      .click();
    await expectNotification(page, expectedNotification);
  });

  await waitForQueryParams(page, { page: 'adminvps', action: 'list' });
  await expect(vpsListRow(page, vpsId)).toBeVisible();

  await waitForVpsTransactionsSettled(page, vpsId);
  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

test.describe.serial('VPS admin core browser coverage', () => {
  let savedVpsId;
  let savedHostname;
  let customVpsId;
  let customHostname;

  test('admin create wizard handles user selection and final variants', async ({ page }) => {
    await login(page, fixtures.admin);

    savedHostname = hostname('webui-admin-saved');
    savedVpsId = await createAdminVps(page, fixtures, savedHostname, adminCreateOptions({
      bootAfterCreate: true,
      info: 'Webui admin create saved user data',
      userData: {
        type: 'saved',
        id: fixtures.user.userData.id,
      },
    }));

    customHostname = hostname('webui-admin-custom');
    customVpsId = await createAdminVps(page, fixtures, customHostname, adminCreateOptions({
      bootAfterCreate: false,
      info: 'Webui admin create custom user data',
      userData: {
        type: 'custom',
        format: 'script',
        content: "#!/bin/sh\nprintf 'webui admin custom create\\n' > /root/webui-admin-create.txt\n",
      },
    }));

    await logout(page, fixtures.admin.username);
  });

  test('admin list filters submit and row actions are wired', async ({ page }) => {
    expect(savedVpsId).toBeTruthy();
    expect(customVpsId).toBeTruthy();

    await login(page, fixtures.admin);

    await submitAdminListFilters(page, {
      environmentId: fixtures.environment.id,
      fromId: savedVpsId - 1,
      limit: 25,
      locationId: fixtures.location.id,
      nodeId: fixtures.node.id,
      objectState: 'active',
      userId: fixtures.user.id,
      userNamespaceMapId: fixtures.user.userNamespaceMap.id,
    });

    let filterForm = page.locator('form[name="vps-filter"]');
    await expect(filterForm.locator('input[name="limit"]')).toHaveValue('25');
    await expect(filterForm.locator('input[name="from_id"]')).toHaveValue(String(savedVpsId - 1));
    await expect(filterForm.locator('input[name="user"]')).toHaveValue(String(fixtures.user.id));
    await expect(filterForm.locator('select[name="node"]')).toHaveValue(String(fixtures.node.id));
    await expect(filterForm.locator('select[name="location"]')).toHaveValue(String(fixtures.location.id));
    await expect(filterForm.locator('select[name="environment"]')).toHaveValue(String(fixtures.environment.id));
    await expect(filterForm.locator('select[name="object_state"]')).toHaveValue('active');
    await expect(filterForm.locator('input[name="user_namespace_map"]')).toHaveValue(
      String(fixtures.user.userNamespaceMap.id),
    );
    await expect(vpsListRow(page, savedVpsId)).toContainText(savedHostname);

    await submitAdminListFilters(page, {
      fromId: savedVpsId - 1,
      limit: 1,
      userId: fixtures.user.id,
    });

    filterForm = page.locator('form[name="vps-filter"]');
    await expect(filterForm.locator('input[name="limit"]')).toHaveValue('1');
    await expect(filterForm.locator('input[name="from_id"]')).toHaveValue(String(savedVpsId - 1));
    await expect(listDataRows(page)).toHaveCount(1);
    await expect(vpsListRow(page, savedVpsId)).toBeVisible();

    await expectAdminRowActionLinks(page, savedVpsId);
    await runFilteredListAction(page, savedVpsId, 'restart', 'Restart of', 'running');
    await runFilteredListAction(page, savedVpsId, 'stop', 'Stop VPS', 'stopped');

    await openAdminVpsListAround(page, customVpsId);
    await expect(vpsListRow(page, customVpsId).locator('img[title="Unable to restart"]')).toBeVisible();
    await expect(vpsListRow(page, customVpsId).locator(`a[href*="run=start"][href*="veid=${customVpsId}"]`)).toBeVisible();
    await expect(vpsListRow(page, customVpsId).locator(`a[href*="action=migrate-step-1"][href*="veid=${customVpsId}"]`)).toBeVisible();
    await expect(vpsListRow(page, customVpsId).locator(`a[href*="action=delete"][href*="veid=${customVpsId}"]`)).toBeVisible();
    await runFilteredListAction(page, customVpsId, 'start', 'Start of', 'running');

    await logout(page, fixtures.admin.username);
  });

  test('admin detail actions and admin-only forms submit', async ({ page }) => {
    expect(customVpsId).toBeTruthy();

    await login(page, fixtures.admin);

    await gotoVpsDetail(page, customVpsId);
    await expect(page.locator('#content-in h1')).toContainText('[Admin mode]');
    await expect(page.locator('#aside a', { hasText: 'State log' })).toBeVisible();

    await runDetailAction(page, customVpsId, 'stop', 'Stop VPS', 'stopped', { confirm: false });
    await runDetailAction(page, customVpsId, 'start', 'Start of', 'running', { confirm: false });
    await runDetailAction(page, customVpsId, 'restart', 'Restart of', 'running', { confirm: false });
    await runDetailAction(page, customVpsId, 'force_restart', 'Force restart VPS', 'running', { confirm: false });
    await runDetailAction(page, customVpsId, 'force_stop', 'Force stop VPS', 'stopped', { confirm: false });
    await runDetailAction(page, customVpsId, 'start', 'Start of', 'running', { confirm: false });

    await submitAdminResources(page, customVpsId, {
      changeReason: 'Webui admin resource form coverage',
      cpuLimit: 75,
    });
    await submitAdminNetworkInterface(page, customVpsId, {
      maxRx: 16,
      maxTx: 8,
    });
    await disableAdminNetwork(page, customVpsId, 'Webui admin disable network coverage');
    await enableAdminNetwork(page, customVpsId);
    await setAdminAutostartPriority(page, customVpsId, 321);
    await setAdminMapMode(page, customVpsId);
    await setAdminObjectState(page, customVpsId, {
      changeReason: 'Webui admin lifetime form coverage',
      expirationDate: futureDateTime(7),
    });

    await gotoVpsDetail(page, customVpsId);
    const stateLogLink = page.locator('#aside a', { hasText: 'State log' });
    await expect(stateLogLink).toBeVisible();
    await stateLogLink.click();
    await expect(page).toHaveURL(new RegExp(`page=lifetimes.*action=changelog.*resource=vps.*id=${customVpsId}`));
    await expect(page.locator('#content-in')).toContainText(`State log for vps #${customVpsId}`);

    await logout(page, fixtures.admin.username);
  });
});
