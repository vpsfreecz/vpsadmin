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

function rowWithText(page, text) {
  return page.locator('table.table-style01 tr', { hasText: text }).first();
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

async function setSelectIfPresent(form, name, value) {
  const select = form.locator(`select[name="${name}"]`);

  if ((await select.count()) === 0) {
    return false;
  }

  await select.selectOption(String(value));
  return true;
}

async function submitAndExpect(page, form, button, notification) {
  await submitForm(form, button);
  await expectStorageNotification(page, notification);
}

async function expectStorageNotification(page, text) {
  await expect(page.locator('#perex', { hasText: text }).first()).toContainText(text);
}

async function openDatasetEdit(page, datasetId, role = 'primary') {
  await page.goto(
    `/?page=dataset&action=edit&role=${role}&id=${datasetId}&return=%2F%3Fpage%3Dbackup`,
    { waitUntil: 'domcontentloaded' },
  );
  await expect(page.locator('#content-in')).toContainText('Edit dataset');
}

async function submitDatasetEdit(page, datasetId, role = 'primary', options = {}) {
  await openDatasetEdit(page, datasetId, role);

  const form = formByAction(page, `action=edit&role=${role}&id=${datasetId}`);
  await expect(form).toBeVisible();

  if (options.quota !== undefined) {
    const quotaName = role === 'hypervisor' ? 'refquota' : 'quota';
    await form.locator(`input[name="${quotaName}"]`).fill(String(options.quota));
    await form.locator('select[name="quota_unit"]').selectOption(options.unit || 'g');
  }

  if (options.adminOverride !== undefined) {
    await setCheckbox(form, 'admin_override', options.adminOverride);
  }

  if (options.adminLockType) {
    await setSelectIfPresent(form, 'admin_lock_type', options.adminLockType);
  }

  await submitAndExpect(page, form, 'Save', 'Dataset updated');
}

async function submitExportSettings(page, exportId, options = {}) {
  await page.goto(`/?page=export&action=edit&export=${exportId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText(`NFS export #${exportId}`);

  const form = formByAction(page, `action=edit&export=${exportId}`);
  await expect(form).toBeVisible();

  for (const [name, enabled] of Object.entries(options.checkboxes || {})) {
    await setCheckbox(form, name, enabled);
  }

  if (options.threads !== undefined) {
    const threads = form.locator('input[name="threads"]');
    if ((await threads.count()) > 0) {
      await threads.fill(String(options.threads));
    }
  }

  await submitAndExpect(page, form, 'Save', 'Export settings updated');
}

async function submitExportStatus(page, exportId, action, button, notification) {
  await page.goto(`/?page=export&action=edit&export=${exportId}`, {
    waitUntil: 'domcontentloaded',
  });

  const form = formByAction(page, `action=${action}&export=${exportId}`);
  await expect(form).toBeVisible();
  await submitAndExpect(page, form, button, notification);
}

module.exports = {
  actionLink,
  expectStorageNotification,
  openDatasetEdit,
  rowWithText,
  setCheckbox,
  setSelectIfPresent,
  submitAndExpect,
  submitDatasetEdit,
  submitExportSettings,
  submitExportStatus,
};
