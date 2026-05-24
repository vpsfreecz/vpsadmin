const { expect } = require('@playwright/test');

const {
  gotoVpsDetail,
  waitForVpsStatus,
  waitForVpsTransactionsSettled,
} = require('./webui.cjs');

const CONSOLE_OPERATION_TIMEOUT = 10 * 60 * 1000;

async function openConsole(page, vpsId) {
  await gotoVpsDetail(page, vpsId);
  await page.locator(`a[href*="page=console"][href*="veid=${vpsId}"]`, {
    hasText: 'Remote console',
  }).first().click();
  await expect(page).toHaveURL(new RegExp(`page=console.*veid=${vpsId}`));
  await expect(page.locator('#perex')).toContainText(/Remote Console for VPS|No console server available/);
}

async function expectConsoleIframe(page, vpsId) {
  await openConsole(page, vpsId);

  const iframe = page.locator('#vpsadmin-console-frame');
  if ((await iframe.count()) === 0) {
    await expect(page.locator('#perex')).toContainText('No console server available');
    return false;
  }

  await expect(iframe).toBeVisible();

  const src = await iframe.getAttribute('src');
  expect(src).toBeTruthy();

  const url = new URL(src);
  expect(url.pathname).toBe(`/console/${vpsId}`);
  expect(url.searchParams.get('session')).toMatch(/[A-Za-z0-9_-]+/);
  expect(url.searchParams.get('auth_type')).toBeNull();
  expect(url.searchParams.get('auth_token')).toBeNull();

  return true;
}

async function runConsoleVpsAction(page, vpsId, command, label, expectedStatus) {
  await openConsole(page, vpsId);

  const status = page.locator('#vps-action-status');
  await page.locator(`#aside a[href*="vps_do('${command}')"]`).click();

  await expect(status).toContainText(new RegExp(`^${escapeRegExp(label)} (planned|done|\\.\\.\\.)$`));
  await expect(status).toContainText(new RegExp(`^${escapeRegExp(label)} done$`), {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function generateConsoleRootPassword(page, vpsId) {
  await openConsole(page, vpsId);

  const password = page.locator('#root-password');
  await expect(password).toContainText('will be generated');
  await page.locator('#aside button', { hasText: 'Generate password' }).click();
  await expect(password).toContainText('configuring password...');
  await expect(password).toContainText(/^[a-zA-Z2-9]{8}$/, {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  await waitForVpsTransactionsSettled(page, vpsId);
}

async function bootConsoleRescue(page, vpsId, osTemplateId) {
  await openConsole(page, vpsId);

  await page.locator('#aside select[name="os_template"]').selectOption(String(osTemplateId));
  await page.locator('#aside input[name="root_mountpoint"]').fill('/mnt/webui-rescue');
  await page.locator('#boot-button').click();
  await expect(page.locator('#boot-button')).toContainText('Booting...');
  await expect(page.locator('#boot-button')).toContainText('Boot', {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  bootConsoleRescue,
  expectConsoleIframe,
  generateConsoleRootPassword,
  openConsole,
  runConsoleVpsAction,
};
