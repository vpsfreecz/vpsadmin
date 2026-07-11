const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  waitForDetailValue,
  waitForVpsStatus,
} = require('../lib/pages/webui.cjs');
const {
  changeVpsOwner,
  cloneAdminVps,
  createAdminVps,
  deleteAdminVps,
  migrateVps,
  previewVpsSwap,
  replaceVps,
  submitVpsSwapPreview,
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

const languageFlag = (page, locale) =>
  page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`);

async function switchLanguage(page, locale) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
    languageFlag(page, locale).click(),
  ]);
}

function adminCreateOptions(options = {}) {
  return {
    bootAfterCreate: false,
    nodeId: fixtures.node.id,
    userId: fixtures.user.id,
    ...options,
    resources: {
      ...smallResources,
      ...(options.resources || {}),
    },
  };
}

function secondaryUser() {
  const user = fixtures.users && fixtures.users.secondary;

  if (!user || !user.id || !user.username) {
    throw new Error('vps-admin-ops requires a secondary user fixture');
  }

  return user;
}

function secondaryLocationId() {
  const secondary = fixtures.locations && fixtures.locations.secondary;

  if (!secondary || !secondary.id || secondary.id === fixtures.location.id) {
    throw new Error('vps-admin-ops requires a secondary location fixture');
  }

  return secondary.id;
}

function node2() {
  const node = fixtures.cluster && fixtures.cluster.nodes && fixtures.cluster.nodes.node2;

  if (!node || !node.id || !node.domainName) {
    throw new Error('vps-admin-ops requires node2 fixture data');
  }

  if (node.locationId === fixtures.node.locationId) {
    throw new Error('vps-admin-ops requires node2 in a different location');
  }

  return node;
}

test.describe.serial('VPS admin long operation browser coverage', () => {
  test('admin change owner preview, cancel, and confirm paths work', async ({ page }) => {
    const targetUser = secondaryUser();

    await login(page, fixtures.admin);

    const vpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-chown'),
      adminCreateOptions(),
    );

    await changeVpsOwner(page, vpsId, targetUser, { cancel: true });
    await waitForDetailValue(page, vpsId, 'Owner', new RegExp(fixtures.user.username));

    await changeVpsOwner(page, vpsId, targetUser);
    await waitForDetailValue(page, vpsId, 'Owner', new RegExp(targetUser.username));

    await logout(page, fixtures.admin.username);
  });

  test('admin migrate wizard submits cross-node preferences', async ({ page }) => {
    const targetNode = node2();
    const reason = 'Webui admin migrate coverage';

    await login(page, fixtures.admin);

    const vpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-migrate'),
      adminCreateOptions({
        bootAfterCreate: false,
      }),
    );

    await migrateVps(page, vpsId, targetNode, {
      cleanupData: false,
      maintenanceWindow: false,
      noStart: true,
      reason,
      replaceIpAddresses: true,
      requireReplaceIpAddresses: true,
      requireTransferIpAddresses: true,
      sendMail: false,
      skipStart: true,
      transferIpAddresses: true,
    });
    await waitForVpsStatus(page, vpsId, 'stopped');

    await logout(page, fixtures.admin.username);
  });

  test('admin clone wizard submits target user, node, and option fields', async ({ page }) => {
    const targetUser = secondaryUser();
    const targetNode = node2();
    const clonedHostname = hostname('webui-admin-clone-copy');

    await login(page, fixtures.admin);

    const sourceVpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-clone-src'),
      adminCreateOptions(),
    );

    const clonedVpsId = await cloneAdminVps(page, fixtures, sourceVpsId, clonedHostname, {
      dataset_plans: false,
      features: false,
      locationId: secondaryLocationId(),
      nodeDomainName: targetNode.domainName,
      nodeId: targetNode.id,
      resources: false,
      stop: false,
      userId: targetUser.id,
      userLogin: targetUser.username,
    });
    expect(clonedVpsId).not.toBe(sourceVpsId);

    await logout(page, fixtures.admin.username);
  });

  test('admin swap preview and submit include admin-only options', async ({ page }) => {
    const targetNode = node2();
    const swapOptions = {
      expirations: true,
      hostname: true,
      resources: true,
    };

    await login(page, fixtures.admin);

    const primaryVpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-swap-a'),
      adminCreateOptions({
        bootAfterCreate: true,
      }),
    );
    const secondaryVpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-swap-b'),
      adminCreateOptions({
        bootAfterCreate: true,
        locationId: secondaryLocationId(),
        nodeId: targetNode.id,
      }),
    );

    await previewVpsSwap(page, primaryVpsId, secondaryVpsId, swapOptions);

    try {
      await switchLanguage(page, 'cs_CZ.utf8');
      const preview = page.locator('#content-in');
      await expect(preview).toContainText(
        new RegExp(`Prohodit VPS\\s+#${primaryVpsId}\\s+s VPS\\s+#${secondaryVpsId}`),
      );
      await expect(preview).toContainText('Nyní');
      await expect(preview).toContainText('Po výměně');
      await expect(preview).toContainText('První migrace:');
      await expect(preview).toContainText('Druhá migrace:');
      await expect(preview).toContainText('Délka odstávky:');
      await expect(preview).toContainText('Prostředí:');
      await expect(preview).toContainText('Vypršení platnosti:');
      await expect(preview).toContainText('Paměť:');
      await expect(preview).toContainText('IP adresy:');
      await expect(preview).toContainText('Změněné atributy jsou označeny zeleně.');
      await expect(preview.locator('img[alt="změní se na"]')).toHaveCount(2);
      await expect(page.locator('input[type="submit"][value="Prohodit VPS"]')).toBeVisible();
    } finally {
      await switchLanguage(page, 'en_US.utf8');
    }

    await submitVpsSwapPreview(page, primaryVpsId, secondaryVpsId, swapOptions);

    await logout(page, fixtures.admin.username);
  });

  test('admin replace form submits node, expiration, backup flags, start, reason, and confirm', async ({ page }) => {
    const targetNode = node2();

    await login(page, fixtures.admin);

    const sourceVpsId = await createAdminVps(
      page,
      fixtures,
      hostname('webui-admin-replace'),
      adminCreateOptions(),
    );

    const replacementVpsId = await replaceVps(page, sourceVpsId, targetNode, {
      expirationDate: futureDateTime(30),
      preserveBackups: false,
      preserveBackupHistory: false,
      reason: 'Webui admin replace coverage',
      start: true,
    });
    expect(replacementVpsId).not.toBe(sourceVpsId);

    await logout(page, fixtures.admin.username);
  });

  test('admin delete form submits with lazy delete checked and unchecked', async ({ page }) => {
    await login(page, fixtures.admin);

    const lazyHostname = hostname('webui-admin-delete-lazy');
    const lazyVpsId = await createAdminVps(
      page,
      fixtures,
      lazyHostname,
      adminCreateOptions(),
    );

    const hardHostname = hostname('webui-admin-delete-hard');
    const hardVpsId = await createAdminVps(
      page,
      fixtures,
      hardHostname,
      adminCreateOptions(),
    );

    await deleteAdminVps(page, lazyVpsId, {
      hostname: lazyHostname,
      lazy: true,
    });

    await deleteAdminVps(page, hardVpsId, {
      hostname: hardHostname,
      lazy: false,
      waitForTransactions: false,
    });
  });
});
