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

async function setCheckbox(checkbox, enabled) {
  if (enabled) {
    await checkbox.check();
  } else {
    await checkbox.uncheck();
  }
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

async function selectCreateLocation(page, fixtures, userId, options = {}) {
  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select a location');

  const locationId = options.locationId || fixtures.location.id;
  const locationForm = page.locator('form[name="newvps-step2"]');
  await chooseRadio(locationForm.locator(`input[name="location"][value="${locationId}"]`));
  await submitForm(locationForm);

  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select distribution');
  await expect(page).toHaveURL(new RegExp(`user=${userId || ''}`));
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
}

async function createVps(page, fixtures, hostname, options = {}) {
  await page.goto('/?page=adminvps&action=new-step-1', { waitUntil: 'domcontentloaded' });
  await selectCreateLocation(page, fixtures, '', options);
  const finalForm = formByAction(page, 'action=new-submit');
  await finalForm.locator('input[name="hostname"]').fill(hostname);
  const userNamespaceSelect = finalForm.locator('select[name="user_namespace_map"]');
  if ((await userNamespaceSelect.count()) > 0) {
    await userNamespaceSelect.selectOption(String(options.userNamespaceMapId || fixtures.user.userNamespaceMap.id));
  }
  await selectUserData(finalForm, options.userData || { type: 'none' });
  await finalForm
    .locator('input[type="submit"], button[type="submit"], button:not([type])')
    .last()
    .click({ timeout: 60 * 1000 });

  await expectNotification(page, 'VPS create');
  const vpsId = vpsIdFromCurrentUrl(page);
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');

  return vpsId;
}

async function createAdminVps(page, fixtures, hostname, options = {}) {
  const userId = options.userId || fixtures.user.id;

  await page.goto('/?page=adminvps&action=new-step-0', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Select user');

  const userForm = page.locator('form[name="newvps-step0"]');
  await expect(userForm.locator('input[name="user"]')).toBeVisible();
  await userForm.locator('input[name="user"]').fill(String(userId));
  await submitForm(userForm, 'Next');

  await selectCreateLocation(page, fixtures, userId, options);

  const finalForm = formByAction(page, 'action=new-submit');
  const nodeId = String(options.nodeId || fixtures.node.id);
  await expect(finalForm.locator('select[name="node"]')).toBeVisible();
  await finalForm.locator('select[name="node"]').selectOption(nodeId);
  await finalForm.locator('input[name="hostname"]').fill(hostname);
  await setCheckbox(
    finalForm.locator('input[name="boot_after_create"]'),
    options.bootAfterCreate !== false,
  );
  await finalForm.locator('textarea[name="info"]').fill(options.info || '');
  await selectUserData(finalForm, options.userData || { type: 'none' });
  await finalForm
    .locator('input[type="submit"], button[type="submit"], button:not([type])')
    .last()
    .click({ timeout: 60 * 1000 });

  await expectNotification(page, 'VPS create');
  const vpsId = vpsIdFromCurrentUrl(page);
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, options.bootAfterCreate === false ? 'stopped' : 'running');

  return vpsId;
}

async function cloneVps(page, fixtures, sourceVpsId, hostname, options = {}) {
  const locationId = options.locationId || fixtures.location.id;

  await page.goto(`/?page=adminvps&action=clone-step-1&veid=${sourceVpsId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in h1')).toContainText('Clone a VPS: Select a location');

  const locationForm = page.locator('form[name="clonevps-step1"]');
  await chooseRadio(locationForm.locator(`input[name="location"][value="${locationId}"]`));
  await submitForm(locationForm);

  await expect(page.locator('#content-in h1')).toContainText('Clone a VPS: Final touches');
  const finalForm = formByAction(page, 'action=clone-submit');
  await expect(finalForm.locator('select[name="node"]')).toHaveCount(0);
  await finalForm.locator('input[name="hostname"]').fill(hostname);

  for (const field of ['dataset_plans', 'resources', 'features', 'stop']) {
    if (options[field] === undefined) {
      continue;
    }

    const checkbox = finalForm.locator(`input[name="${field}"]`);
    if ((await checkbox.count()) === 0) {
      continue;
    }

    if (options[field]) {
      await checkbox.check();
    } else {
      await checkbox.uncheck();
    }
  }

  await Promise.all([
    page.waitForURL(/action=info.*veid=\d+/, { timeout: 2 * 60 * 1000 }),
    finalForm
      .locator('input[type="submit"], button[type="submit"], button:not([type])')
      .first()
      .click({ noWaitAfter: true, timeout: 60 * 1000 }),
  ]);

  await expectNotification(page, 'Clone in progress');
  const clonedVpsId = vpsIdFromCurrentUrl(page);
  await waitForVpsTransactionsSettled(page, clonedVpsId);

  return clonedVpsId;
}

async function previewVpsSwap(page, primaryVpsId, secondaryVpsId) {
  await page.goto(`/?page=adminvps&action=swap&veid=${primaryVpsId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in h1')).toContainText(`VPS #${primaryVpsId}`);

  const swapForm = formByAction(page, 'action=swap_preview', { name: 'vps-swap' });
  const select = swapForm.locator('select[name="vps"]');

  if ((await select.count()) > 0) {
    await select.selectOption(String(secondaryVpsId));
  } else {
    await swapForm.locator('input[name="vps"]').fill(String(secondaryVpsId));
  }

  await submitForm(swapForm, 'Preview');

  await expect(page).toHaveURL(/action=swap_preview/);
  await expect(page.locator('#content-in')).toContainText(
    new RegExp(`Replace VPS\\s+#${primaryVpsId}\\s+with\\s+#${secondaryVpsId}`),
  );
  await expect(page.locator('#content-in')).toContainText('First migration');
  await expect(page.locator('#content-in')).toContainText('Second migration');
}

async function submitVpsSwapPreview(page, primaryVpsId, secondaryVpsId) {
  const previewForm = formByAction(page, `action=swap&veid=${primaryVpsId}`);
  await expect(previewForm.locator(`input[name="vps"][value="${secondaryVpsId}"]`)).toHaveCount(1);
  await submitForm(previewForm, /Go/);

  await expectNotification(page, 'Swap in progress');
  await expect(page).toHaveURL(new RegExp(`action=info.*veid=${primaryVpsId}`));
  await waitForVpsTransactionsSettled(page, primaryVpsId);
  await waitForVpsTransactionsSettled(page, secondaryVpsId);
}

async function deleteStoppedVps(page, vpsId, hostname) {
  await page.goto(`/?page=adminvps&action=delete&veid=${vpsId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#perex')).toContainText(`delete VPS number ${vpsId}`);
  if (hostname) {
    await expect(page.locator('#content-in')).toContainText(hostname);
  }

  const form = formByAction(page, 'action=delete2');
  await expect(form.locator('input[name="lazy_delete"]')).toHaveCount(0);
  await submitForm(form, 'Delete');

  await expectNotification(page, `Delete VPS #${vpsId}`);
  await expect(page).toHaveURL(/page=adminvps/);
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function expectUserAdminOnlyControlsHidden(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  await expect(page.locator('#content-in h1')).toContainText('[User mode]');
  await expect(page.locator('#aside a', { hasText: 'Migrate VPS' })).toHaveCount(0);
  await expect(page.locator('#aside a', { hasText: 'Change owner' })).toHaveCount(0);
  await expect(page.locator('#aside a', { hasText: 'Replace VPS' })).toHaveCount(0);
  await expect(page.locator('#aside a[href*="action=clone-step-0"]')).toHaveCount(0);
  await expect(page.locator('#aside a[href*="action=clone-step-1"]', { hasText: 'Clone VPS' })).toBeVisible();

  const resourcesForm = formByAction(page, 'action=resources');
  await expect(resourcesForm.locator('input[name="cpu_limit"]')).toHaveCount(0);
  await expect(resourcesForm.locator('textarea[name="change_reason"]')).toHaveCount(0);
  await expect(resourcesForm.locator('input[name="admin_override"]')).toHaveCount(0);
  await expect(resourcesForm.locator('select[name="admin_lock_type"]')).toHaveCount(0);

  const netifForm = formByAction(page, 'action=netif');
  await expect(netifForm.locator('input[name="max_tx"]')).toHaveCount(0);
  await expect(netifForm.locator('input[name="max_rx"]')).toHaveCount(0);
  await expect(netifForm.locator('input[name="enable"]')).toHaveCount(0);

  await expect(page.locator('form[action*="action=autostart"]')).toHaveCount(0);
  await expect(page.locator('form[action*="action=map_mode"]')).toHaveCount(0);
  await expect(page.locator('form[action*="action=disable_network"]')).toHaveCount(0);
  await expect(page.locator('form[action*="action=enable_network"]')).toHaveCount(0);
  await expect(page.locator('#content-in h2', { hasText: 'Auto-Start' })).toHaveCount(0);
  await expect(page.locator('#content-in h2', { hasText: 'Map mode' })).toHaveCount(0);
  await expect(page.locator('#content-in h2', { hasText: /Disable network|Enable network/ })).toHaveCount(0);
}

async function gotoVpsList(page) {
  await page.goto('/?page=adminvps&action=list', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in h1')).toContainText('VPS list');
}

function vpsListRow(page, vpsId) {
  return page.locator('table.table-style01 tr', {
    has: page.locator(`a[href*="action=info&veid=${vpsId}"]`),
  }).first();
}

async function runListAction(page, vpsId, action, expectedNotification, expectedStatus, options = {}) {
  await gotoVpsList(page);

  if (['stop', 'restart'].includes(action) && options.confirm !== false) {
    await acceptNextDialog(page);
  }

  const clickAction = async () => {
    await vpsListRow(page, vpsId)
      .locator(`a[href*="run=${action}"][href*="veid=${vpsId}"]`)
      .first()
      .click();
    await expectNotification(page, expectedNotification);
  };

  if (options.confirm === false) {
    await withoutDialogs(page, clickAction);
  } else {
    await clickAction();
  }

  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function runDetailAction(page, vpsId, action, expectedNotification, expectedStatus, options = {}) {
  await gotoVpsDetail(page, vpsId);

  if (['stop', 'restart', 'force_restart', 'force_stop'].includes(action) && options.confirm !== false) {
    await acceptNextDialog(page);
  }

  const clickAction = async () => {
    await page.locator(`a[href*="run=${action}"][href*="veid=${vpsId}"]`).first().click();
    await expectNotification(page, expectedNotification);
  };

  if (options.confirm === false) {
    await withoutDialogs(page, clickAction);
  } else {
    await clickAction();
  }

  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function stopVpsIfRunning(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const stopAction = page.locator(`a[href*="run=stop"][href*="veid=${vpsId}"]`).first();
  if ((await stopAction.count()) === 0) {
    return;
  }

  await acceptNextDialog(page);
  await stopAction.click();
  await expectNotification(page, 'Stop VPS');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'stopped');
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

async function submitAdminResources(page, vpsId, options = {}) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=resources');
  await expect(form.locator('input[name="cpu_limit"]')).toBeVisible();
  await expect(form.locator('textarea[name="change_reason"]')).toBeVisible();
  await expect(form.locator('input[name="admin_override"]')).toBeVisible();
  await expect(form.locator('select[name="admin_lock_type"]')).toBeVisible();

  await form.locator('input[name="cpu_limit"]').fill(String(options.cpuLimit || 75));
  await form.locator('textarea[name="change_reason"]').fill(options.changeReason || 'Webui admin resource coverage');
  await setCheckbox(form.locator('input[name="admin_override"]'), options.adminOverride !== false);
  await form.locator('select[name="admin_lock_type"]').selectOption(options.adminLockType || 'no_lock');
  await submitForm(form);

  await expectNotification(page, 'Resources changed');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=resources').locator('input[name="cpu_limit"]')).toHaveValue(
    String(options.cpuLimit || 75),
  );
}

async function submitAdminNetworkInterface(page, vpsId, options = {}) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=netif');
  await expect(form.locator('input[name="max_tx"]')).toBeVisible();
  await expect(form.locator('input[name="max_rx"]')).toBeVisible();
  await expect(form.locator('input[name="enable"]')).toBeVisible();

  await form.locator('input[name="max_tx"]').fill(String(options.maxTx || 8));
  await form.locator('input[name="max_rx"]').fill(String(options.maxRx || 16));
  await setCheckbox(form.locator('input[name="enable"]'), options.enable !== false);
  await submitForm(form);

  await expectNotification(page, 'Interface updated');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  const updatedForm = formByAction(page, 'action=netif');
  await expect(updatedForm.locator('input[name="max_tx"]')).toHaveValue(String(options.maxTx || 8));
  await expect(updatedForm.locator('input[name="max_rx"]')).toHaveValue(String(options.maxRx || 16));
  await expect(updatedForm.locator('input[name="enable"]')).toBeChecked();
}

async function disableAdminNetwork(page, vpsId, reason) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=disable_network');
  await expect(form.locator('input[name="disable_network"]')).toBeVisible();
  await expect(form.locator('textarea[name="change_reason"]')).toBeVisible();
  await form.locator('input[name="disable_network"]').check();
  await form.locator('textarea[name="change_reason"]').fill(reason || 'Webui admin disable network coverage');
  await submitForm(form);

  await expectNotification(page, 'Network disabled');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=enable_network')).toBeVisible();
}

async function enableAdminNetwork(page, vpsId) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=enable_network');
  await expect(form).toBeVisible();
  await submitForm(form);

  await expectNotification(page, 'Network enabled');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=disable_network')).toBeVisible();
}

async function setAdminAutostartPriority(page, vpsId, priority) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=autostart');
  await expect(form.locator('input[name="autostart_priority"]')).toBeVisible();
  await form.locator('input[name="autostart_priority"]').fill(String(priority));
  await submitForm(form);

  await expectNotification(page, 'Auto-Start priority set');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=autostart').locator('input[name="autostart_priority"]')).toHaveValue(
    String(priority),
  );
}

async function setAdminMapMode(page, vpsId, mode = null) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=map_mode');
  const select = form.locator('select[name="map_mode"]');
  await expect(select).toBeVisible();

  const currentMode = await select.inputValue();
  const targetMode = mode || (currentMode === 'zfs' ? 'native' : 'zfs');
  await select.selectOption(targetMode);
  await submitForm(form);

  await expectNotification(page, 'Map mode set');
  await waitForVpsTransactionsSettled(page, vpsId);
  await gotoVpsDetail(page, vpsId);
  await expect(formByAction(page, 'action=map_mode').locator('select[name="map_mode"]')).toHaveValue(targetMode);
}

async function setAdminObjectState(page, vpsId, options = {}) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=set_state');
  await expect(form.locator('select[name="object_state"]')).toBeVisible();
  await expect(form.locator('input[name="expiration_date"]')).toBeVisible();
  await expect(form.locator('textarea[name="change_reason"]')).toBeVisible();
  await form.locator('select[name="object_state"]').selectOption(options.state || 'active');
  await form.locator('input[name="expiration_date"]').fill(options.expirationDate || '2026-05-19 00:00:00');
  await form.locator('textarea[name="change_reason"]').fill(options.changeReason || 'Webui admin state coverage');
  await submitForm(form);

  await expectNotification(page, 'State set');
  await expect(page).toHaveURL(new RegExp(`page=adminvps.*veid=${vpsId}`));
  await expect(page.locator('table.table-style01 tr', { hasText: 'Expiration:' }).first()).toBeVisible();
}

module.exports = {
  addAndRemoveRoutedIpAndHostAddress,
  bootFromTemplate,
  chooseRadio,
  createAdminVps,
  cloneVps,
  createVps,
  deleteStoppedVps,
  disableAdminNetwork,
  enableAdminNetwork,
  deployPublicKey,
  expectUserAdminOnlyControlsHidden,
  gotoVpsList,
  openRemoteConsole,
  previewVpsSwap,
  reinstallVps,
  reinstallVpsWithOptions,
  renameNetworkInterface,
  resetRootPassword,
  runListAction,
  runDetailAction,
  selectFirstUsableOption,
  setAdminModifications,
  setAdminAutostartPriority,
  setAdminMapMode,
  setAdminObjectState,
  setCgroupVersion,
  setDnsResolverMode,
  setDistributionInformation,
  setHostnameManual,
  setHostname,
  setMaintenanceWindowsPerDay,
  setMaintenanceWindowsUnified,
  setCheckbox,
  setOsTemplateAutoUpdate,
  setStartMenuTimeout,
  setUserNamespaceMap,
  stopVpsIfRunning,
  submitAdminNetworkInterface,
  submitAdminResources,
  submitVpsSwapPreview,
  submitFeatures,
  updateResources,
  vpsListRow,
  vpsIdFromCurrentUrl,
};
