const { expect } = require('@playwright/test');

const {
  acceptNextDialog,
  expectNotification,
  formByAction,
  gotoVpsDetail,
  submitForm,
  waitForDetailValue,
  waitForVpsTransactionsSettled,
  waitForVpsStatus,
} = require('./webui.cjs');

function vpsIdFromCurrentUrl(page) {
  const url = new URL(page.url());
  const id = url.searchParams.get('veid');

  if (!id) {
    throw new Error(`Unable to find veid in ${page.url()}`);
  }

  return Number.parseInt(id, 10);
}

async function chooseRadio(locator) {
  if (await locator.isChecked()) {
    return;
  }

  try {
    await locator.check({ force: true, timeout: 5000 });
  } catch (error) {
    await locator.evaluate((el) => {
      el.checked = true;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }

  await expect(locator).toBeChecked();
}

async function selectFirstUsableOption(select, options = {}) {
  const preferredValue = options.preferredValue === undefined ? null : String(options.preferredValue);
  const choices = await select.locator('option').evaluateAll((elements) =>
    elements.map((option) => ({
      disabled: option.disabled,
      label: option.textContent.trim(),
      value: option.value,
    })),
  );

  const usable = choices.filter((option) =>
    !option.disabled
      && option.value !== ''
      && option.value !== '0'
      && option.label !== '-------',
  );
  const selected = usable.find((option) => option.value === preferredValue) || usable[0];

  if (!selected) {
    throw new Error('No usable select option found');
  }

  await select.selectOption(selected.value);
  return selected;
}

async function selectUserData(form, userData = { type: 'none' }) {
  const type = userData.type || 'none';

  await chooseRadio(form.locator(`input[name="user_data_type"][value="${type}"]`));

  if (type === 'saved') {
    await form.locator('select[name="vps_user_data"]').selectOption(String(userData.id));
  } else if (type === 'custom') {
    if (userData.format) {
      await form.locator('select[name="user_data_format"]').selectOption(String(userData.format));
    }

    await form.locator('[name="user_data_content"]').fill(userData.content || '');
  }
}

async function fillCreateResources(form, fixtures, overrides = {}) {
  const resources = {
    ...fixtures.vps.resources,
    ...overrides,
  };

  for (const [name, value] of Object.entries(resources)) {
    const input = form.locator(`input[name="${name}"]`);

    if ((await input.count()) > 0) {
      await input.fill(String(value));
    }
  }
}

async function createVps(page, fixtures, hostname, options = {}) {
  await page.goto('/?page=adminvps&action=new-step-1', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select a location');

  const locationForm = page.locator('form[name="newvps-step2"]');
  await chooseRadio(locationForm.locator(`input[name="location"][value="${fixtures.location.id}"]`));
  await submitForm(locationForm);

  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select distribution');
  await page.locator('details').first().evaluate((el) => {
    el.open = true;
  });

  const distributionForm = page.locator('form[name="newvps-step2"]');
  await chooseRadio(
    distributionForm.locator(`input[name="os_template"][value="${fixtures.osTemplates.primary.id}"]`),
  );
  await submitForm(distributionForm);

  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Specify parameters');
  const paramsForm = page.locator('form[name="newvps-step3"]');
  await fillCreateResources(paramsForm, fixtures, options.resources);
  await submitForm(paramsForm);

  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Final touches');
  const finalForm = formByAction(page, 'action=new-submit');
  await finalForm.locator('input[name="hostname"]').fill(hostname);
  const userNamespaceSelect = finalForm.locator('select[name="user_namespace_map"]');
  if ((await userNamespaceSelect.count()) > 0) {
    await userNamespaceSelect.selectOption(String(options.userNamespaceMapId || fixtures.user.userNamespaceMap.id));
  }
  await selectUserData(finalForm, options.userData || { type: 'none' });
  await submitForm(finalForm);

  await expectNotification(page, 'VPS create');
  const vpsId = vpsIdFromCurrentUrl(page);
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');

  return vpsId;
}

async function gotoVpsList(page) {
  await page.goto('/?page=adminvps', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('VPS list');
}

function vpsListRow(page, vpsId) {
  return page.locator('table.table-style01 tr', {
    has: page.locator(`a[href*="action=info&veid=${vpsId}"]`),
  }).first();
}

async function runListAction(page, vpsId, action, expectedNotification, expectedStatus) {
  await gotoVpsList(page);

  if (['stop', 'restart'].includes(action)) {
    await acceptNextDialog(page);
  }

  await vpsListRow(page, vpsId)
    .locator(`a[href*="run=${action}"][href*="veid=${vpsId}"]`)
    .first()
    .click();
  await expectNotification(page, expectedNotification);
  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function runDetailAction(page, vpsId, action, expectedNotification, expectedStatus) {
  await gotoVpsDetail(page, vpsId);

  if (['stop', 'restart', 'force_restart', 'force_stop'].includes(action)) {
    await acceptNextDialog(page);
  }

  await page.locator(`a[href*="run=${action}"][href*="veid=${vpsId}"]`).first().click();
  await expectNotification(page, expectedNotification);
  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function resetRootPassword(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=passwd');
  await chooseRadio(form.locator('input[name="password_type"][value="simple"]'));
  await submitForm(form);

  await expectNotification(page, 'Change of root password planned');
  await expect(page.locator('#perex b')).toContainText(/[a-zA-Z2-9]{8}/);
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function deployPublicKey(page, vpsId, publicKeyId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=pubkey');
  await form.locator('select[name="public_key"]').selectOption(String(publicKeyId));
  await submitForm(form);

  await expectNotification(page, 'Public key deployment planned');
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function setDnsResolverMode(page, vpsId, mode) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=nameserver');
  await chooseRadio(form.locator(`input[name="manage_dns_resolver"][value="${mode}"]`));
  if (mode === 'managed') {
    await selectFirstUsableOption(form.locator('select[name="nameserver"]'));
  }
  await submitForm(form);

  await expectNotification(page, 'DNS change planned');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(
    formByAction(page, 'action=nameserver').locator(
      `input[name="manage_dns_resolver"][value="${mode}"]`,
    ),
  ).toBeChecked();
}

async function setHostname(page, vpsId, hostname) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=hostname');
  await chooseRadio(form.locator('input[name="manage_hostname"][value="managed"]'));
  await form.locator('input[name="hostname"]').fill(hostname);
  await submitForm(form);

  await expectNotification(page, 'Hostname change planned');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForDetailValue(page, vpsId, 'Hostname', new RegExp(`^${hostname}$`));
}

async function setHostnameManual(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=hostname');
  await chooseRadio(form.locator('input[name="manage_hostname"][value="manual"]'));
  await submitForm(form);

  await expectNotification(page, 'Hostname change planned');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(
    formByAction(page, 'action=hostname').locator('input[name="manage_hostname"][value="manual"]'),
  ).toBeChecked();
}

async function renameNetworkInterface(page, vpsId, name) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=netif');
  await expect(form).toBeVisible();
  await form.locator('input[name="name"]').fill(name);
  await submitForm(form);

  await expectNotification(page, 'Interface updated');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=netif').locator('input[name="name"]').first()).toHaveValue(name);
}

async function addAndRemoveRoutedIpAndHostAddress(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const routeSelectForm = formByAction(page, 'action=iproute_select');
  await selectFirstUsableOption(routeSelectForm.locator('select[name="iproute_type"]'), {
    preferredValue: 'ipv4',
  });
  await submitForm(routeSelectForm, 'Continue');

  await expect(page.locator('#content-in h1')).toContainText('Add route');
  const routeAddForm = formByAction(page, 'action=iproute_add');
  const route = await selectFirstUsableOption(routeAddForm.locator('select[name="addr"]'));
  await submitForm(routeAddForm, 'Add route');

  await expectNotification(page, 'Addition of IP address planned');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(page.locator('#content-in')).toContainText(route.label.split(/\s+/)[0].replace(/\/.+$/, ''));

  const hostAddressForm = formByAction(page, 'action=hostaddr_add');
  await selectFirstUsableOption(hostAddressForm.locator('select[name="hostaddr_public_v4"]'));
  await submitForm(hostAddressForm);

  await expectNotification(page, 'Addition of IP address planned');
  await waitForVpsTransactionsSettled(page, vpsId);

  await gotoVpsDetail(page, vpsId);
  await page.locator(`a[href*="action=hostaddr_del"][href*="veid=${vpsId}"]`).first().click();
  await expectNotification(page, 'Deletion of IP address planned');
  await waitForVpsTransactionsSettled(page, vpsId);

  await gotoVpsDetail(page, vpsId);
  await page.locator(`a[href*="action=iproute_del"][href*="veid=${vpsId}"]`).first().click();
  await expectNotification(page, 'Deletion of IP address planned');
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function openRemoteConsole(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  await page.locator(`a[href*="page=console"][href*="veid=${vpsId}"]`, {
    hasText: /open remote console|Remote console/,
  }).first().click();
  await expect(page).toHaveURL(new RegExp(`page=console.*veid=${vpsId}`));
  await expect(page.locator('#perex')).toContainText(new RegExp(`Remote Console for VPS|No console server available`));
}

async function reinstallVpsWithOptions(page, vpsId, fixtures, options = {}) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=reinstall');
  const osTemplate = options.osTemplate || fixtures.osTemplates.reinstall;
  await form.locator('select[name="os_template"]').selectOption(String(osTemplate.id));
  await selectUserData(form, options.userData || { type: 'none' });
  await submitForm(form, /Reinstall/);

  await expect(page.locator('#content-in h2', { hasText: 'Confirm reinstallation' })).toBeVisible();
  const confirmForm = formByAction(page, 'action=reinstall');

  if (options.cancel) {
    await confirmForm.locator('input[type="submit"][name="cancel"]').click();
    await gotoVpsDetail(page, vpsId);
    return;
  }

  await confirmForm.locator('input[name="confirm"]').check();
  await confirmForm.locator('input[type="submit"][name="reinstall"]').click();

  await expectNotification(page, 'Reinstallation of VPS');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForDetailValue(
    page,
    vpsId,
    'Distribution',
    new RegExp(osTemplate.label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
  );
  await waitForVpsStatus(page, vpsId, 'running');
}

async function reinstallVps(page, vpsId, fixtures) {
  await reinstallVpsWithOptions(page, vpsId, fixtures, {
    osTemplate: fixtures.osTemplates.reinstall,
    userData: {
      type: 'saved',
      id: fixtures.user.userData.id,
    },
  });
}

async function bootFromTemplate(page, vpsId, osTemplate) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=boot');
  await form.locator('select[name="os_template"]').selectOption(String(osTemplate.id));
  await chooseRadio(form.locator('input[name="mount_root_dataset"][value="no"]'));
  await submitForm(form, 'Boot');

  await expectNotification(page, 'will be rebooted momentarily');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');
}

async function setDistributionInformation(page, vpsId, osTemplate) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=os_template');
  await form.locator('select[name="os_template"]').selectOption(String(osTemplate.id));
  await submitForm(form, 'Save');

  await expectNotification(page, 'Distribution information updated');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForDetailValue(
    page,
    vpsId,
    'Distribution',
    new RegExp(osTemplate.label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
  );
}

async function setOsTemplateAutoUpdate(page, vpsId, enabled) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=toggle_os_template_auto_update');
  const checkbox = form.locator('input[name="enable_os_template_auto_update"]');

  if (enabled) {
    await checkbox.check();
  } else {
    await checkbox.uncheck();
  }

  await submitForm(form, 'Save');
  await expectNotification(
    page,
    enabled ? 'Reading of /etc/release was enabled' : 'Reading of /etc/release was disabled',
  );
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function updateResources(page, vpsId, resources) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=resources');
  for (const [name, value] of Object.entries(resources)) {
    await form.locator(`input[name="${name}"]`).fill(String(value));
  }
  await submitForm(form);

  await expectNotification(page, 'Resources changed');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);

  for (const [name, value] of Object.entries(resources)) {
    await expect(formByAction(page, 'action=resources').locator(`input[name="${name}"]`)).toHaveValue(String(value));
  }
}

async function submitFeatures(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=features');
  await expect(form).toBeVisible();
  await submitForm(form);

  await expectNotification(page, 'Features set');
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function setStartMenuTimeout(page, vpsId, timeout) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=startmenu');
  await form.locator('input[name="timeout"]').fill(String(timeout));
  await submitForm(form);

  await expectNotification(page, 'Start menu set');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=startmenu').locator('input[name="timeout"]')).toHaveValue(String(timeout));
}

async function setCgroupVersion(page, vpsId, cgroupVersion) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=setcgroup');
  await chooseRadio(form.locator(`input[name="cgroup_version"][value="${cgroupVersion}"]`));
  await submitForm(form);

  await expectNotification(page, 'Cgroup version set');
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function setAdminModifications(page, vpsId, enabled) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=setmodifications');
  await chooseRadio(form.locator(`input[name="allow_admin_modifications"][value="${enabled ? '1' : '0'}"]`));
  await submitForm(form);

  await expectNotification(page, 'VPS modifications preference set');
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function setMaintenanceWindowsUnified(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=maintenance_windows');
  await chooseRadio(form.locator('input[name="unified"][value="1"]'));
  await form.locator('select[name="unified_opens_at"]').selectOption('1');
  await form.locator('select[name="unified_closes_at"]').selectOption('3');
  await submitForm(form);

  await expectNotification(page, 'Maintenance windows set');
}

async function setMaintenanceWindowsPerDay(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=maintenance_windows');
  await chooseRadio(form.locator('input[name="unified"][value="0"]'));
  const firstOpen = form.locator('input[name="is_open[]"]').first();
  if (!(await firstOpen.isChecked())) {
    await firstOpen.check();
  }
  await form.locator('select[name="opens_at[]"]').first().selectOption('2');
  await form.locator('select[name="closes_at[]"]').first().selectOption('4');
  await submitForm(form);

  await expectNotification(page, 'Maintenance windows set');
}

async function setUserNamespaceMap(page, vpsId, userNamespaceMapId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=userns_map');
  const select = form.locator('select[name="user_namespace_map"]');
  await expect(select).toBeVisible();
  await select.selectOption(String(userNamespaceMapId));
  await submitForm(form);

  await expectNotification(page, 'VPS user namespace mapping updated');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=userns_map').locator('select[name="user_namespace_map"]')).toHaveValue(String(userNamespaceMapId));
}

module.exports = {
  addAndRemoveRoutedIpAndHostAddress,
  bootFromTemplate,
  chooseRadio,
  createVps,
  deployPublicKey,
  gotoVpsList,
  openRemoteConsole,
  reinstallVps,
  reinstallVpsWithOptions,
  renameNetworkInterface,
  resetRootPassword,
  runListAction,
  runDetailAction,
  selectFirstUsableOption,
  setAdminModifications,
  setCgroupVersion,
  setDnsResolverMode,
  setDistributionInformation,
  setHostnameManual,
  setHostname,
  setMaintenanceWindowsPerDay,
  setMaintenanceWindowsUnified,
  setOsTemplateAutoUpdate,
  setStartMenuTimeout,
  setUserNamespaceMap,
  submitFeatures,
  updateResources,
  vpsListRow,
};
