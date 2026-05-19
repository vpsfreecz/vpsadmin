const { expect } = require('@playwright/test');

function content(page) {
  return page.locator('#content-in');
}

function heading(page) {
  return page.locator('#content-in h1').first();
}

function rowWithText(scope, text) {
  return scope.locator('table.table-style01 tr', { hasText: text }).first();
}

function actionLink(scope, action, params = {}) {
  let selector = `a[href*="action=${action}"]`;

  for (const [key, value] of Object.entries(params)) {
    selector += `[href*="${key}=${value}"]`;
  }

  return scope.locator(selector).first();
}

async function gotoCluster(page, action = null, params = {}) {
  const query = new URLSearchParams({ page: 'cluster' });

  if (action) {
    query.set('action', action);
  }

  for (const [key, value] of Object.entries(params)) {
    query.set(key, String(value));
  }

  await page.goto(`/?${query.toString()}`, { waitUntil: 'domcontentloaded' });
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

async function fillIfPresent(form, selector, value) {
  const field = form.locator(selector).first();

  if ((await field.count()) === 0) {
    return false;
  }

  await field.fill(String(value));
  return true;
}

async function selectIfPresent(form, name, value) {
  const field = form.locator(`[name="${name}"]`).first();

  if ((await field.count()) === 0) {
    return false;
  }

  await field.selectOption(String(value));
  return true;
}

function linkParam(link, name) {
  return link.getAttribute('href').then((href) => {
    if (!href) {
      throw new Error(`Link has no href while reading ${name}`);
    }

    return new URL(href, 'http://webui.vpsadmin.test/').searchParams.get(name);
  });
}

module.exports = {
  actionLink,
  content,
  fillIfPresent,
  gotoCluster,
  heading,
  linkParam,
  rowWithText,
  selectIfPresent,
  setCheckbox,
};
