const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { expectNotification, gotoVpsDetail } = require('../lib/pages/webui.cjs');
const {
  addAndRemoveRoutedIpAndHostAddress,
  bootFromTemplate,
  createVps,
  gotoVpsList,
  openRemoteConsole,
  reinstallVpsWithOptions,
  renameNetworkInterface,
  runDetailAction,
  runListAction,
  setAdminModifications,
  setCgroupVersion,
  setDnsResolverMode,
  setDistributionInformation,
  setHostnameManual,
  setMaintenanceWindowsPerDay,
  setMaintenanceWindowsUnified,
  setOsTemplateAutoUpdate,
  setStartMenuTimeout,
  setUserNamespaceMap,
  submitFeatures,
  updateResources,
  vpsListRow,
} = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();

function hostname(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

test.describe.serial('VPS user core browser coverage', () => {
  let savedVpsId;
  let savedHostname;
  let customVpsId;
  let customHostname;

  test('user create wizard handles variants and invalid steps', async ({ page }) => {
    await login(page, fixtures.user);

    await page.goto('/?page=adminvps&action=new-step-2&user=&location=999999', {
      waitUntil: 'domcontentloaded',
    });
    await expectNotification(page, 'Invalid location');
    await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select a location');
    await expect(page).toHaveURL(/action=new-step-1/);

    await page.goto(
      `/?page=adminvps&action=new-step-3&user=&location=${fixtures.location.id}&os_template=999999`,
      { waitUntil: 'domcontentloaded' },
    );
    await expectNotification(page, 'Invalid distribution');
    await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select distribution');
    await expect(page).toHaveURL(/action=new-step-2/);

    savedHostname = hostname('webui-saved');
    savedVpsId = await createVps(page, fixtures, savedHostname, {
      userData: {
        type: 'saved',
        id: fixtures.user.userData.id,
      },
      userNamespaceMapId: fixtures.user.userNamespaceMap.id,
    });

    customHostname = hostname('webui-custom');
    customVpsId = await createVps(page, fixtures, customHostname, {
      userData: {
        type: 'custom',
        format: 'script',
        content: "#!/bin/sh\nprintf 'webui custom create\\n' > /root/webui-custom-create.txt\n",
      },
      userNamespaceMapId: fixtures.user.userNamespaceMap.id,
    });

    await logout(page, fixtures.user.username);
  });

  test('user list page renders row actions for running and stopped VPSes', async ({ page }) => {
    expect(savedVpsId).toBeTruthy();

    await login(page, fixtures.user);
    await gotoVpsList(page);

    await expect(page.locator('#content-in h1')).toContainText('[User mode]');
    await expect(page.locator('form[name="vps-filter"]')).toHaveCount(0);

    let row = vpsListRow(page, savedVpsId);
    await expect(row).toContainText(savedHostname);
    await expect(row.locator(`a[href*="run=restart"][href*="veid=${savedVpsId}"]`)).toBeVisible();
    await expect(row.locator(`a[href*="run=stop"][href*="veid=${savedVpsId}"]`)).toBeVisible();
    await expect(row.locator(`a[href*="page=console"][href*="veid=${savedVpsId}"]`)).toBeVisible();
    await expect(row.locator(`a[href*="action=delete"][href*="veid=${savedVpsId}"]`)).toHaveCount(0);
    await expect(row.locator('img[title="Stop the VPS to be able to delete it"]')).toBeVisible();

    await runListAction(page, savedVpsId, 'restart', 'Restart of', 'running');
    await runListAction(page, savedVpsId, 'stop', 'Stop VPS', 'stopped');

    await gotoVpsList(page);
    row = vpsListRow(page, savedVpsId);
    await expect(row.locator('img[title="Unable to restart"]')).toBeVisible();
    await expect(row.locator(`a[href*="run=start"][href*="veid=${savedVpsId}"]`)).toBeVisible();
    await expect(row.locator(`a[href*="action=delete"][href*="veid=${savedVpsId}"]`)).toBeVisible();

    await runListAction(page, savedVpsId, 'start', 'Start of', 'running');
    await logout(page, fixtures.user.username);
  });

  test('user detail actions and forms submit expected core values', async ({ page }) => {
    expect(customVpsId).toBeTruthy();

    await login(page, fixtures.user);

    await runDetailAction(page, customVpsId, 'force_restart', 'Force restart VPS', 'running');
    await runDetailAction(page, customVpsId, 'force_stop', 'Force stop VPS', 'stopped');
    await runDetailAction(page, customVpsId, 'start', 'Start of', 'running');

    await openRemoteConsole(page, customVpsId);

    await setDnsResolverMode(page, customVpsId, 'manual');
    await setDnsResolverMode(page, customVpsId, 'managed');
    await setHostnameManual(page, customVpsId);
    await renameNetworkInterface(page, customVpsId, `ethuc${Date.now().toString(36).slice(-6)}`);
    await addAndRemoveRoutedIpAndHostAddress(page, customVpsId);
    await updateResources(page, customVpsId, {
      cpu: 2,
      memory: 1536,
      swap: 0,
    });
    await submitFeatures(page, customVpsId);
    await setStartMenuTimeout(page, customVpsId, 7);
    await setCgroupVersion(page, customVpsId, 'cgroup_any');
    await setAdminModifications(page, customVpsId, false);
    await setAdminModifications(page, customVpsId, true);
    await setMaintenanceWindowsUnified(page, customVpsId);
    await setMaintenanceWindowsPerDay(page, customVpsId);
    await setUserNamespaceMap(page, customVpsId, fixtures.user.alternateUserNamespaceMap.id);

    await logout(page, fixtures.user.username);
  });

  test('user reinstall, distribution, auto-update, and rescue boot forms work', async ({ page }) => {
    await login(page, fixtures.user);

    const vpsId = await createVps(page, fixtures, hostname('webui-reinstall'), {
      userNamespaceMapId: fixtures.user.userNamespaceMap.id,
    });

    await reinstallVpsWithOptions(page, vpsId, fixtures, {
      osTemplate: fixtures.osTemplates.reinstall,
      userData: { type: 'none' },
      cancel: true,
    });
    await gotoVpsDetail(page, vpsId);
    await expect(page.locator('#content-in h1')).toContainText(`VPS #${vpsId}`);

    await reinstallVpsWithOptions(page, vpsId, fixtures, {
      osTemplate: fixtures.osTemplates.reinstall,
      userData: { type: 'none' },
    });
    await reinstallVpsWithOptions(page, vpsId, fixtures, {
      osTemplate: fixtures.osTemplates.primary,
      userData: {
        type: 'custom',
        format: 'script',
        content: "#!/bin/sh\nprintf 'webui reinstall custom\\n' > /root/webui-reinstall-custom.txt\n",
      },
    });

    await setDistributionInformation(page, vpsId, fixtures.osTemplates.reinstall);
    await setOsTemplateAutoUpdate(page, vpsId, true);
    await setOsTemplateAutoUpdate(page, vpsId, false);
    await bootFromTemplate(page, vpsId, fixtures.osTemplates.primary);

    await logout(page, fixtures.user.username);
  });
});
