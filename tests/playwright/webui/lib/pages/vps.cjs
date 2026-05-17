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

async function createVps(page, fixtures, hostname) {
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
  await paramsForm.locator('input[name="memory"]').fill(String(fixtures.vps.resources.memory));
  await paramsForm.locator('input[name="cpu"]').fill(String(fixtures.vps.resources.cpu));
  await paramsForm.locator('input[name="swap"]').fill(String(fixtures.vps.resources.swap));
  await paramsForm.locator('input[name="diskspace"]').fill(String(fixtures.vps.resources.diskspace));
  await paramsForm.locator('input[name="ipv4"]').fill(String(fixtures.vps.resources.ipv4));
  await paramsForm.locator('input[name="ipv4_private"]').fill(String(fixtures.vps.resources.ipv4_private));
  await paramsForm.locator('input[name="ipv6"]').fill(String(fixtures.vps.resources.ipv6));
  await submitForm(paramsForm);

  await expect(page.locator('#content-in h1')).toContainText('Create a VPS: Final touches');
  const finalForm = formByAction(page, 'action=new-submit');
  await finalForm.locator('input[name="hostname"]').fill(hostname);
  const userNamespaceSelect = finalForm.locator('select[name="user_namespace_map"]');
  if ((await userNamespaceSelect.count()) > 0) {
    await userNamespaceSelect.selectOption(String(fixtures.user.userNamespaceMap.id));
  }
  await chooseRadio(finalForm.locator('input[name="user_data_type"][value="none"]'));
  await submitForm(finalForm);

  await expectNotification(page, 'VPS create');
  const vpsId = vpsIdFromCurrentUrl(page);
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');

  return vpsId;
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

async function reinstallVps(page, vpsId, fixtures) {
  await gotoVpsDetail(page, vpsId);

  const form = formByAction(page, 'action=reinstall');
  await form.locator('select[name="os_template"]').selectOption(String(fixtures.osTemplates.reinstall.id));
  await chooseRadio(form.locator('input[name="user_data_type"][value="saved"]'));
  await form.locator('select[name="vps_user_data"]').selectOption(String(fixtures.user.userData.id));
  await submitForm(form, /Reinstall/);

  await expect(page.locator('#content-in h2', { hasText: 'Confirm reinstallation' })).toBeVisible();
  const confirmForm = formByAction(page, 'action=reinstall');
  await confirmForm.locator('input[name="confirm"]').check();
  await confirmForm.locator('input[type="submit"][name="reinstall"]').click();

  await expectNotification(page, 'Reinstallation of VPS');
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForDetailValue(
    page,
    vpsId,
    'Distribution',
    new RegExp(fixtures.osTemplates.reinstall.label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
  );
  await waitForVpsStatus(page, vpsId, 'running');
}

module.exports = {
  createVps,
  deployPublicKey,
  reinstallVps,
  resetRootPassword,
  runDetailAction,
  setDnsResolverMode,
  setHostname,
};
