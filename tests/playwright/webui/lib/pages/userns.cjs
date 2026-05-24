const { expect } = require('@playwright/test');

const { expectNotification, formByAction, submitForm } = require('./webui.cjs');

function userNamespaceRow(page, id) {
  return page.locator('tr', {
    has: page.locator(`a[href="?page=userns&action=show&id=${id}"]`),
  }).first();
}

function userNamespaceMapRow(page, id) {
  return page.locator('tr', {
    has: page.locator(`a[href="?page=userns&action=map_show&id=${id}"]`),
  }).first();
}

function mapEntriesForm(page) {
  return page.locator('form[name="userns-map-entries"]');
}

function mapEntryRows(page) {
  return page.locator('form[name="userns-map-entries"] tr', {
    has: page.locator('input[name="entry_id[]"]'),
  });
}

async function gotoUserNamespaceMap(page, id, label = null) {
  await page.goto(`/?page=userns&action=map_show&id=${id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in h1')).toContainText(`UID/GID map #${id}`);

  if (label) {
    await expect(page.locator('#content-in h1')).toContainText(label);
  }
}

async function mapEntryRowByValues(page, values) {
  const rows = await mapEntryRows(page).all();

  for (const row of rows) {
    const kind = (await row.locator('td').first().innerText()).trim().toLowerCase();

    if (values.kind && kind !== values.kind.toLowerCase()) {
      continue;
    }

    const vpsId = await row.locator('input[name="vps_id[]"]').inputValue();
    const nsId = await row.locator('input[name="ns_id[]"]').inputValue();
    const count = await row.locator('input[name="count[]"]').inputValue();

    if (
      (values.vpsId === undefined || vpsId === String(values.vpsId)) &&
      (values.nsId === undefined || nsId === String(values.nsId)) &&
      (values.count === undefined || count === String(values.count))
    ) {
      return row;
    }
  }

  throw new Error(`No UID/GID map entry matched ${JSON.stringify(values)}`);
}

async function expectNoMapEntryByValues(page, values) {
  const rows = await mapEntryRows(page).all();

  for (const row of rows) {
    const kind = (await row.locator('td').first().innerText()).trim().toLowerCase();
    const vpsId = await row.locator('input[name="vps_id[]"]').inputValue();
    const nsId = await row.locator('input[name="ns_id[]"]').inputValue();
    const count = await row.locator('input[name="count[]"]').inputValue();

    expect({
      kind,
      vpsId,
      nsId,
      count,
    }).not.toEqual({
      kind: values.kind.toLowerCase(),
      vpsId: String(values.vpsId),
      nsId: String(values.nsId),
      count: String(values.count),
    });
  }
}

async function renameUserNamespaceMap(page, id, label) {
  const form = formByAction(page, `action=map_edit&id=${id}`);
  await form.locator('input[name="label"]').fill(label);
  await submitForm(form);
  await expectNotification(page, 'Label changed');
  await expect(page.locator('#content-in h1')).toContainText(label);
}

async function saveMapEntries(page) {
  await submitForm(mapEntriesForm(page), /Save/);
  await expectNotification(page, 'Map updated');
}

async function addMapEntries(page, values) {
  const form = mapEntriesForm(page);
  await form.locator('select[name="new_kind"]').selectOption(values.kind);
  await form.locator('input[name="new_vps_id"]').fill(String(values.vpsId));
  await form.locator('input[name="new_ns_id"]').fill(String(values.nsId));
  await form.locator('input[name="new_count"]').fill(String(values.count));
  await submitForm(form, /Add/);
  await expectNotification(page, 'Entry added');
}

async function deleteMapEntry(page, values) {
  const row = await mapEntryRowByValues(page, values);
  await row.locator('a[href*="action=map_entry_del"]').click();
  await expectNotification(page, 'Entry removed');
}

async function createUserNamespaceMap(page, label, options = {}) {
  await page.goto('/?page=userns&action=map_new', { waitUntil: 'domcontentloaded' });

  const form = formByAction(page, 'action=map_new');
  if (options.userNamespaceId) {
    const namespaceSelect = form.locator('select[name="user_namespace"]');
    const namespaceInput = form.locator('input[name="user_namespace"]:not([type="hidden"])');

    if (await namespaceSelect.count()) {
      await namespaceSelect.selectOption(String(options.userNamespaceId));
    } else if (await namespaceInput.count()) {
      await namespaceInput.fill(String(options.userNamespaceId));
    }
  }
  await form.locator('input[name="label"]').fill(label);
  await submitForm(form);
  await expectNotification(page, 'Map created');

  const url = new URL(page.url());
  const id = Number.parseInt(url.searchParams.get('id'), 10);

  if (!id) {
    throw new Error(`Created map id not found in ${page.url()}`);
  }

  await expect(page.locator('#content-in h1')).toContainText(label);

  return id;
}

async function deleteUserNamespaceMap(page, id) {
  await page.goto('/?page=userns&action=maps', { waitUntil: 'domcontentloaded' });
  await userNamespaceMapRow(page, id)
    .locator(`a[href*="action=map_del&id=${id}&t="]`)
    .click();
  await expectNotification(page, 'Map deleted');
}

module.exports = {
  addMapEntries,
  createUserNamespaceMap,
  deleteMapEntry,
  deleteUserNamespaceMap,
  expectNoMapEntryByValues,
  gotoUserNamespaceMap,
  mapEntriesForm,
  mapEntryRowByValues,
  renameUserNamespaceMap,
  saveMapEntries,
  userNamespaceMapRow,
  userNamespaceRow,
};
