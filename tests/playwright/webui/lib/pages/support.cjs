const { expect } = require('@playwright/test');

const {
  expectNotification,
  formByAction,
  submitForm,
} = require('./webui.cjs');

function rowWithText(scope, text) {
  return scope.locator('table.table-style01 tr', { hasText: String(text) }).first();
}

function rowWithLink(scope, hrefPart) {
  return scope.locator('table.table-style01 tr', {
    has: scope.locator(`a[href*="${hrefPart}"]`),
  }).first();
}

function linkWithParams(scope, params = {}) {
  let selector = 'a';

  for (const [key, value] of Object.entries(params)) {
    selector += `[href*="${key}=${value}"]`;
  }

  return scope.locator(selector).first();
}

async function hrefParam(locator, name, baseUrl) {
  const href = await locator.getAttribute('href');

  if (!href) {
    throw new Error(`Link has no href while reading ${name}`);
  }

  return new URL(href, baseUrl).searchParams.get(name);
}

async function setCheckboxIfPresent(form, name, checked) {
  const checkbox = form.locator(`input[name="${name}"]`);

  if ((await checkbox.count()) === 0) {
    return false;
  }

  if (checked) {
    await checkbox.check();
    await expect(checkbox).toBeChecked();
  } else {
    await checkbox.uncheck();
    await expect(checkbox).not.toBeChecked();
  }

  return true;
}

async function selectIfPresent(form, name, value) {
  const select = form.locator(`select[name="${name}"]`);

  if ((await select.count()) === 0) {
    return false;
  }

  await select.selectOption(value);
  return true;
}

async function submitConfirmedForm(form, button) {
  await setCheckboxIfPresent(form, 'confirm', true);
  await submitForm(form, button);
}

async function submitMonitoringAction(page, action, eventId, notification) {
  await page.goto(`/?page=monitoring&action=${action}&id=${eventId}`, {
    waitUntil: 'domcontentloaded',
  });

  const form = formByAction(page, `action=${action}&id=${eventId}`);
  await expect(form).toBeVisible();
  await submitConfirmedForm(form, action === 'ack' ? 'Acknowledge' : 'Ignore');
  await expectNotification(page, notification);
}

module.exports = {
  hrefParam,
  linkWithParams,
  rowWithLink,
  rowWithText,
  selectIfPresent,
  setCheckboxIfPresent,
  submitConfirmedForm,
  submitMonitoringAction,
};
