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

async function expectDnsNotification(page, text) {
  await expect(page.locator('#perex', { hasText: text }).first()).toContainText(text);
}

async function createPrimaryZone(page, name, options = {}) {
  await page.goto('/?page=dns&action=primary_zone_new', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Create a new primary DNS zone');

  const form = formByAction(page, 'action=primary_zone_new2');
  await expect(form).toBeVisible();

  if (options.userId) {
    await form.locator('input[name="user"]').fill(String(options.userId));
  }

  await form.locator('input[name="name"]').fill(name);
  await form.locator('input[name="email"]').fill(options.email || 'hostmaster@example.test');
  await submitForm(form, 'Create zone');
  await expectDnsNotification(page, 'Primary DNS zone created');
}

async function createSecondaryZone(page, name, options = {}) {
  await page.goto('/?page=dns&action=secondary_zone_new', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Create a new secondary DNS zone');

  const form = formByAction(page, 'action=secondary_zone_new2');
  await expect(form).toBeVisible();

  if (options.userId) {
    await form.locator('input[name="user"]').fill(String(options.userId));
  }

  await form.locator('input[name="name"]').fill(name);
  await submitForm(form, 'Create zone');
  await expectDnsNotification(page, 'Secondary DNS zone created');
}

async function submitZoneDelete(page, zone) {
  await page.goto(`/?page=dns&action=zone_delete&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('Delete zone');

  const form = formByAction(page, `action=zone_delete2&id=${zone.id}`);
  await expect(form).toBeVisible();
  await setCheckbox(form, 'confirm', true, { required: true });
  await submitForm(form, 'Delete');
  await expectDnsNotification(page, 'DNS zone deleted');
}

async function toggleRecord(page, record, action, enable) {
  await page.goto(`/?page=dns&action=zone_show&id=${record.zoneId}`, {
    waitUntil: 'domcontentloaded',
  });

  await expect(actionLink(page, 'record_edit', { id: record.id })).toBeVisible();
  const link = actionLink(page, action, {
    id: record.id,
    enable: enable ? 1 : 0,
  });
  await expect(link).toBeVisible();

  const href = await link.getAttribute('href');
  expect(href).toContain(`action=${action}`);
  expect(href).toContain(`id=${record.id}`);
  expect(href).toContain(`enable=${enable ? 1 : 0}`);
}

module.exports = {
  actionLink,
  createPrimaryZone,
  createSecondaryZone,
  expectDnsNotification,
  rowWithText,
  setCheckbox,
  submitZoneDelete,
  toggleRecord,
};
