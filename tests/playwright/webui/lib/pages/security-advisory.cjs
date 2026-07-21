const { expect } = require('@playwright/test');

const {
  acceptNextDialog,
  formByAction,
  submitForm,
} = require('./webui.cjs');

function content(page) {
  return page.locator('#content-in');
}

function heading(page) {
  return page.locator('#content-in h1').first();
}

function rowWithText(scope, text) {
  return scope.locator('table.table-style01 tr', { hasText: String(text) }).first();
}

function securityAdvisoryUrl(action, params = {}) {
  const query = new URLSearchParams({
    page: 'security_advisory',
    action,
  });

  for (const [key, value] of Object.entries(params)) {
    query.set(key, String(value));
  }

  return `/?${query.toString()}`;
}

async function gotoAdvisory(page, action, params = {}) {
  await page.goto(securityAdvisoryUrl(action, params), {
    waitUntil: 'domcontentloaded',
  });
}

function cveText(cves) {
  return Array.isArray(cves) ? cves.join(', ') : String(cves);
}

async function fillIfPresent(form, selector, value) {
  const field = form.locator(selector);

  if ((await field.count()) === 0) {
    return false;
  }

  await field.fill(String(value));
  return true;
}

function localizedValue(name, baseValue) {
  const match = name.match(/^([a-z]{2})_/);

  if (!match || match[1] === 'en') {
    return baseValue;
  }

  return `${baseValue} ${match[1]}`;
}

async function fillLocalizedFields(form, values, fields) {
  for (const fieldName of fields) {
    if (values[fieldName] === undefined) {
      continue;
    }

    const fieldsForName = await form.locator(`[name$="_${fieldName}"]`).all();

    for (const field of fieldsForName) {
      const name = await field.getAttribute('name');

      await field.fill(localizedValue(name || '', String(values[fieldName])));
    }
  }
}

async function fillAdvisoryTextFields(form, values) {
  if ('publishedAt' in values) {
    await fillIfPresent(form, 'input[name="published_at"]', values.publishedAt);
  }

  if ('cves' in values) {
    await fillIfPresent(form, 'input[name="cves"]', cveText(values.cves));
  }

  if ('name' in values) {
    await fillIfPresent(form, 'input[name="name"]', values.name);
  }

  await fillLocalizedFields(form, {
    summary: values.summary,
    description: values.description,
    response: values.response,
  }, ['summary', 'description', 'response']);
}

async function fillUpdateTextFields(form, values) {
  if ('state' in values) {
    const state = form.locator('select[name="state"]');

    if ((await state.count()) > 0) {
      await state.selectOption(values.state);
    }
  }

  if ('publishedAt' in values) {
    await fillIfPresent(form, 'input[name="published_at"]', values.publishedAt);
  }

  await fillLocalizedFields(form, {
    summary: values.summary,
    message: values.message,
  }, ['summary', 'message']);
}

function nodeField(form, nodeId, field) {
  return form.locator(`[name="node_${nodeId}_${field}"]`);
}

async function applyNodeStatusDefaults(form, values, nodes = []) {
  if ('state' in values) {
    await form
      .locator('.security-advisory-node-bulk[data-field="state"]')
      .selectOption(values.state);
  }

  const textFields = {
    vulnerableUntil: 'vulnerable_until',
    mitigatedSince: 'mitigated_since',
  };

  for (const [valueName, fieldName] of Object.entries(textFields)) {
    if (!(valueName in values)) {
      continue;
    }

    await form
      .locator(`.security-advisory-node-bulk[data-field="${fieldName}"]`)
      .fill(String(values[valueName]));
  }

  if ('notes' in values) {
    for (const [language, note] of Object.entries(values.notes)) {
      await form
        .locator(`.security-advisory-node-bulk[data-field="${language}_note"]`)
        .fill(String(note));
    }
  }

  await form.locator('input[type="button"][value="Apply"]').click();

  for (const node of nodes) {
    if ('state' in values) {
      await expect(nodeField(form, node.id, 'state')).toHaveValue(values.state);
    }

    if ('vulnerableUntil' in values) {
      await expect(nodeField(form, node.id, 'vulnerable_until')).toHaveValue(
        String(values.vulnerableUntil),
      );
    }

    if ('mitigatedSince' in values) {
      await expect(nodeField(form, node.id, 'mitigated_since')).toHaveValue(
        String(values.mitigatedSince),
      );
    }

    if ('notes' in values) {
      for (const [language, note] of Object.entries(values.notes)) {
        await expect(nodeField(form, node.id, `${language}_note`)).toHaveValue(
          String(note),
        );
      }
    }
  }
}

async function expectNodeStatusInputSizes(form, nodes = []) {
  for (const field of ['vulnerable_until', 'mitigated_since']) {
    await expect(
      form.locator(`.security-advisory-node-bulk[data-field="${field}"]`),
    ).toHaveAttribute('size', '14');
  }

  const bulkNotes = await form
    .locator('.security-advisory-node-bulk[data-field$="_note"]')
    .all();
  expect(bulkNotes.length).toBeGreaterThan(0);
  for (const note of bulkNotes) {
    await expect(note).toHaveAttribute('size', '14');
  }

  for (const node of nodes) {
    for (const field of ['vulnerable_until', 'mitigated_since']) {
      await expect(nodeField(form, node.id, field)).toHaveAttribute('size', '14');
    }

    const notes = await form.locator(
      `input[name^="node_${node.id}_"][name$="_note"]`,
    ).all();
    expect(notes.length).toBeGreaterThan(0);
    for (const note of notes) {
      await expect(note).toHaveAttribute('size', '14');
    }
  }
}

async function setNodeStatus(form, nodeId, values) {
  if ('state' in values) {
    await nodeField(form, nodeId, 'state').selectOption(values.state);
  }

  if ('vulnerableUntil' in values) {
    await nodeField(form, nodeId, 'vulnerable_until').fill(String(values.vulnerableUntil));
  }

  if ('mitigatedSince' in values) {
    await nodeField(form, nodeId, 'mitigated_since').fill(String(values.mitigatedSince));
  }

  if ('notes' in values) {
    for (const [language, note] of Object.entries(values.notes)) {
      await nodeField(form, nodeId, `${language}_note`).fill(String(note));
    }
  }
}

function currentUrlParam(page, name) {
  const value = new URL(page.url()).searchParams.get(name);

  if (!value) {
    throw new Error(`Current URL does not contain ${name}: ${page.url()}`);
  }

  return value;
}

function advisoryIdFromUrl(page) {
  return currentUrlParam(page, 'id');
}

async function paramFromLocatorUrl(page, locator, name, attribute = 'href') {
  const value = await locator.getAttribute(attribute);

  if (!value) {
    throw new Error(`Locator does not contain ${attribute} while reading ${name}`);
  }

  const param = new URL(value, page.url()).searchParams.get(name);

  if (!param) {
    throw new Error(`${attribute} does not contain ${name}: ${value}`);
  }

  return param;
}

async function updateIdFromRow(page, row) {
  return paramFromLocatorUrl(
    page,
    row.locator('a[href*="action=edit_update"]').first(),
    'update',
  );
}

async function linkIdFromForm(page, form) {
  return paramFromLocatorUrl(page, form, 'link', 'action');
}

async function submitConfirmProtectedForm(page, form) {
  await acceptNextDialog(page);
  await form.locator('input[type="image"], input[type="submit"], button').first().click();
  await page.waitForLoadState('domcontentloaded');
}

async function submitSecurityAdvisoryForm(page, actionPart, button = null) {
  const form = formByAction(page, actionPart);
  await expect(form).toBeVisible();
  await submitForm(form, button);
  return form;
}

module.exports = {
  advisoryIdFromUrl,
  applyNodeStatusDefaults,
  content,
  cveText,
  expectNodeStatusInputSizes,
  fillAdvisoryTextFields,
  fillUpdateTextFields,
  formByAction,
  gotoAdvisory,
  heading,
  linkIdFromForm,
  nodeField,
  rowWithText,
  securityAdvisoryUrl,
  setNodeStatus,
  submitConfirmProtectedForm,
  submitSecurityAdvisoryForm,
  updateIdFromRow,
};
