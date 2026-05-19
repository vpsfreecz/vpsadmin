const { expect } = require('@playwright/test');

const {
  formByAction,
  submitForm,
} = require('./webui.cjs');

function actionLink(scope, action, params = {}) {
  let selector = `a[href*="action=${action}"]`;

  for (const [key, value] of Object.entries(params)) {
    selector += `[href*="${key}=${value}"]`;
  }

  return scope.locator(selector).first();
}

function rowWithText(scope, text) {
  return scope.locator('table.table-style01 tr', { hasText: text }).first();
}

async function setCheckbox(form, name, enabled, options = {}) {
  const checkbox = form.locator(`input[name="${name}"]`);

  if ((await checkbox.count()) === 0) {
    if (options.required) {
      throw new Error(`Missing checkbox ${name}`);
    }

    return false;
  }

  if (enabled) {
    await checkbox.check();
    await expect(checkbox).toBeChecked();
  } else {
    await checkbox.uncheck();
    await expect(checkbox).not.toBeChecked();
  }

  return true;
}

async function expectNetworkingNotification(page, text) {
  await expect(page.locator('#perex', { hasText: text }).first()).toContainText(text);
}

async function continueRouteAssign(page, ip, vps, buttonPattern) {
  const form = await expectRouteAssignForm(page, ip, vps);
  await submitForm(form, buttonPattern);
  await expectNetworkingNotification(page, 'IP assigned');
}

async function expectRouteAssignForm(page, ip, vps) {
  await page.goto(`/?page=networking&action=route_assign&id=${ip.id}`, {
    waitUntil: 'domcontentloaded',
  });

  let form = formByAction(page, `action=route_assign&id=${ip.id}`);
  await expect(form).toBeVisible();
  await form.locator('input[name="vps"]').fill(String(vps.id));
  await submitForm(form, 'Continue');

  form = formByAction(page, `action=route_assign&id=${ip.id}`);
  await expect(form).toBeVisible();
  await form.locator('select[name="network_interface"]').selectOption(String(vps.networkInterfaceId));
  await submitForm(form, 'Continue');

  form = formByAction(page, `action=route_assign2&id=${ip.id}`);
  await expect(form).toBeVisible();
  await expect(form).toContainText(vps.networkInterfaceName);

  return form;
}

async function submitConfirmForm(page, actionPart, checkboxName, button, notification, options = {}) {
  const form = formByAction(page, actionPart);
  await expect(form).toBeVisible();

  if (options.extraCheckbox) {
    await setCheckbox(form, options.extraCheckbox, true, { required: true });
  }

  await setCheckbox(form, checkboxName, true, { required: true });
  await submitForm(form, button);
  await expectNetworkingNotification(page, notification);
}

module.exports = {
  actionLink,
  continueRouteAssign,
  expectNetworkingNotification,
  expectRouteAssignForm,
  rowWithText,
  setCheckbox,
  submitConfirmForm,
};
