const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  bootConsoleRescue,
  expectConsoleIframe,
  expectConsoleRootLogin,
  generateConsoleRootPassword,
  runConsoleVpsAction,
} = require('../lib/pages/console.cjs');
const {
  cloneVps,
  createVps,
  deleteStoppedVps,
  expectUserAdminOnlyControlsHidden,
  previewVpsSwap,
  stopVpsIfRunning,
  submitVpsSwapPreview,
} = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();
const smallResources = {
  diskspace: 1024,
};

function hostname(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function createOptions(options = {}) {
  return {
    ...options,
    resources: {
      ...smallResources,
      ...(options.resources || {}),
    },
    userNamespaceMapId: options.userNamespaceMapId || fixtures.user.userNamespaceMap.id,
  };
}

function secondaryLocationId() {
  const secondary = fixtures.locations && fixtures.locations.secondary;

  if (!secondary || !secondary.id || secondary.id === fixtures.location.id) {
    throw new Error('vps-user-ops requires a secondary location fixture');
  }

  return secondary.id;
}

test.describe.serial('VPS user side operations and console coverage', () => {
  test('user clone, swap, delete, and admin gating flows work', async ({ page }) => {
    await login(page, fixtures.user);

    const sourceVpsId = await createVps(page, fixtures, hostname('webui-clone-src'), createOptions());
    await expectUserAdminOnlyControlsHidden(page, sourceVpsId);

    const clonedHostname = hostname('webui-clone-copy');
    const clonedVpsId = await cloneVps(page, fixtures, sourceVpsId, clonedHostname, {
      dataset_plans: false,
      features: false,
      locationId: secondaryLocationId(),
      resources: false,
      stop: false,
    });
    expect(clonedVpsId).not.toBe(sourceVpsId);

    await previewVpsSwap(page, sourceVpsId, clonedVpsId);
    await submitVpsSwapPreview(page, sourceVpsId, clonedVpsId);
    const deleteVpsId = await createVps(page, fixtures, hostname('webui-delete'), createOptions());
    await stopVpsIfRunning(page, deleteVpsId);
    await deleteStoppedVps(page, deleteVpsId);

    await logout(page, fixtures.user.username);
  });

  test('user console sidebar controls use the API', async ({ page }) => {
    await login(page, fixtures.user);

    const vpsId = await createVps(
      page,
      fixtures,
      hostname('webui-console-ops'),
      createOptions({ resources: fixtures.vps.resources }),
    );

    const iframeRendered = await expectConsoleIframe(page, vpsId);
    test.skip(!iframeRendered, 'Fixture location has no remote console server');

    const password = await generateConsoleRootPassword(page, vpsId);
    await expectConsoleRootLogin(page, vpsId, password);
    await bootConsoleRescue(page, vpsId, fixtures.osTemplates.reinstall.id);
    await runConsoleVpsAction(page, vpsId, 'restart', 'Restart', 'running');
    await runConsoleVpsAction(page, vpsId, 'force_restart', 'Reset', 'running');
    await runConsoleVpsAction(page, vpsId, 'stop', 'Stop', 'stopped');
    await runConsoleVpsAction(page, vpsId, 'start', 'Start', 'running');
    await runConsoleVpsAction(page, vpsId, 'force_stop', 'Poweroff', 'stopped');

    await logout(page, fixtures.user.username);
  });
});
