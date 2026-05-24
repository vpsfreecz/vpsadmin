const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { detailValue, formByAction, submitForm } = require('../lib/pages/webui.cjs');
const {
  addMapEntries,
  createUserNamespaceMap,
  deleteMapEntry,
  deleteUserNamespaceMap,
  expectNoMapEntryByValues,
  gotoUserNamespaceMap,
  mapEntryRowByValues,
  mapEntriesForm,
  renameUserNamespaceMap,
  saveMapEntries,
  userNamespaceMapRow,
  userNamespaceRow,
} = require('../lib/pages/userns.cjs');

const fixtures = readFixtures();

test.describe.serial('User namespace browser coverage', () => {
  test('user namespace pages render user-visible data', async ({ page }) => {
    const namespace = fixtures.user.userNamespace;
    const stableMap = fixtures.user.userNamespaceMap;
    const editableMap = fixtures.user.editableUserNamespaceMap;

    await login(page, fixtures.user);

    await page.goto('/?page=userns&action=list', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('User namespaces');

    const namespaceFilter = page.locator('form[name="userns-list"]').first();
    await expect(namespaceFilter).toBeVisible();
    await expect(namespaceFilter.locator('input[name="user"]')).toHaveCount(0);
    await expect(namespaceFilter.locator('input[name="block_count"]')).toHaveCount(0);
    await expect(userNamespaceRow(page, namespace.id)).toContainText(String(namespace.size));

    await page.goto(`/?page=userns&action=show&id=${namespace.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in h1')).toContainText(`User namespace #${namespace.id}`);
    await expect(page.locator('table.table-style01 tr', { hasText: 'ID:' }).first()).toContainText(
      String(namespace.id),
    );
    await expect(page.locator('table.table-style01 tr', { hasText: 'Size:' }).first()).toContainText(
      String(namespace.size),
    );

    await page.goto('/?page=userns&action=maps', { waitUntil: 'domcontentloaded' });
    const mapFilter = page.locator('form[name="userns-map-list"]').first();
    await expect(mapFilter).toBeVisible();
    await expect(mapFilter.locator('input[name="user"]')).toHaveCount(0);
    await expect(mapFilter.locator('input[name="user_namespace"]')).toHaveCount(0);
    await expect(userNamespaceMapRow(page, stableMap.id)).toContainText(stableMap.label);
    await expect(userNamespaceMapRow(page, editableMap.id)).toContainText(editableMap.label);

    await gotoUserNamespaceMap(page, stableMap.id, stableMap.label);
    await expect(formByAction(page, `action=map_edit&id=${stableMap.id}`).locator('input[name="label"]')).toHaveValue(
      stableMap.label,
    );
    await expect(mapEntriesForm(page)).toBeVisible();
    await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: 0,
      nsId: 0,
      count: namespace.size,
    });
    await mapEntryRowByValues(page, {
      kind: 'gid',
      vpsId: 0,
      nsId: 0,
      count: namespace.size,
    });

    await logout(page, fixtures.user.username);
  });

  test('user manages UID/GID maps and entries', async ({ page }) => {
    const editableMap = fixtures.user.editableUserNamespaceMap;
    const uidEntry = editableMap.entries.uid;
    const renamedLabel = `${editableMap.label} ${Date.now().toString(36)}`;
    const temporaryLabel = `Webui Temporary Browser Map ${Date.now().toString(36)}`;
    const addedEntry = {
      vpsId: 42,
      nsId: 10,
      count: 1,
    };

    await login(page, fixtures.user);

    await gotoUserNamespaceMap(page, editableMap.id, editableMap.label);
    await renameUserNamespaceMap(page, editableMap.id, renamedLabel);

    const editableUidRow = await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: uidEntry.vpsId,
      nsId: uidEntry.nsId,
      count: uidEntry.count,
    });
    await editableUidRow.locator('input[name="count[]"]').fill(String(uidEntry.count + 1));
    await saveMapEntries(page);

    await gotoUserNamespaceMap(page, editableMap.id, renamedLabel);
    await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: uidEntry.vpsId,
      nsId: uidEntry.nsId,
      count: uidEntry.count + 1,
    });

    await addMapEntries(page, {
      kind: 'both',
      ...addedEntry,
    });
    await mapEntryRowByValues(page, {
      kind: 'uid',
      ...addedEntry,
    });
    await mapEntryRowByValues(page, {
      kind: 'gid',
      ...addedEntry,
    });

    await deleteMapEntry(page, {
      kind: 'uid',
      ...addedEntry,
    });
    await gotoUserNamespaceMap(page, editableMap.id, renamedLabel);
    await expectNoMapEntryByValues(page, {
      kind: 'uid',
      ...addedEntry,
    });
    await mapEntryRowByValues(page, {
      kind: 'gid',
      ...addedEntry,
    });

    await deleteMapEntry(page, {
      kind: 'gid',
      ...addedEntry,
    });
    await gotoUserNamespaceMap(page, editableMap.id, renamedLabel);
    await expectNoMapEntryByValues(page, {
      kind: 'gid',
      ...addedEntry,
    });

    const resetUidRow = await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: uidEntry.vpsId,
      nsId: uidEntry.nsId,
      count: uidEntry.count + 1,
    });
    await resetUidRow.locator('input[name="count[]"]').fill(String(uidEntry.count));
    await saveMapEntries(page);

    await gotoUserNamespaceMap(page, editableMap.id, renamedLabel);
    await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: uidEntry.vpsId,
      nsId: uidEntry.nsId,
      count: uidEntry.count,
    });
    await renameUserNamespaceMap(page, editableMap.id, editableMap.label);

    const temporaryMapId = await createUserNamespaceMap(page, temporaryLabel, {
      userNamespaceId: fixtures.user.userNamespace.id,
    });
    await page.goto('/?page=userns&action=maps', { waitUntil: 'domcontentloaded' });
    await expect(userNamespaceMapRow(page, temporaryMapId)).toContainText(temporaryLabel);
    await deleteUserNamespaceMap(page, temporaryMapId);
    await expect(userNamespaceMapRow(page, temporaryMapId)).toHaveCount(0);

    await logout(page, fixtures.user.username);
  });

  test('admin manages another user namespace and UID/GID maps', async ({ page }) => {
    const namespace = fixtures.user.userNamespace;
    const stableMap = fixtures.user.userNamespaceMap;
    const temporaryLabel = `Webui Admin Temporary Browser Map ${Date.now().toString(36)}`;
    const renamedLabel = `${temporaryLabel} Renamed`;
    const addedEntry = {
      vpsId: 42,
      nsId: 20,
      count: 2,
    };

    await login(page, fixtures.admin);

    await page.goto('/?page=userns&action=list', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('User namespaces');

    const namespaceFilter = page.locator('form[name="userns-list"]').first();
    await expect(namespaceFilter.locator('input[name="user"]')).toBeVisible();
    await expect(namespaceFilter.locator('input[name="block_count"]')).toBeVisible();
    await namespaceFilter.locator('input[name="user"]').fill(String(fixtures.user.id));
    await namespaceFilter.locator('input[name="block_count"]').fill(String(namespace.blockCount));
    await namespaceFilter.locator('input[name="size"]').fill(String(namespace.size));
    await submitForm(namespaceFilter);

    await expect(namespaceFilter.locator('input[name="user"]')).toHaveValue(String(fixtures.user.id));
    await expect(userNamespaceRow(page, namespace.id)).toContainText(fixtures.user.username);
    await expect(userNamespaceRow(page, namespace.id)).toContainText(String(namespace.offset));
    await expect(userNamespaceRow(page, namespace.id)).toContainText(String(namespace.blockCount));
    await expect(userNamespaceRow(page, namespace.id)).toContainText(String(namespace.size));

    await page.goto(`/?page=userns&action=show&id=${namespace.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in h1')).toContainText(`User namespace #${namespace.id}`);
    expect(await detailValue(page, 'User')).toContain(fixtures.user.username);
    expect(await detailValue(page, 'Offset')).toBe(String(namespace.offset));
    expect(await detailValue(page, 'Blocks')).toBe(String(namespace.blockCount));
    expect(await detailValue(page, 'Size')).toBe(String(namespace.size));

    await page.goto('/?page=userns&action=maps', { waitUntil: 'domcontentloaded' });
    const mapFilter = page.locator('form[name="userns-map-list"]').first();
    await expect(mapFilter.locator('input[name="user"]')).toBeVisible();
    await expect(mapFilter.locator('input[name="user_namespace"]')).toBeVisible();
    await mapFilter.locator('input[name="user"]').fill(String(fixtures.user.id));
    await mapFilter.locator('input[name="user_namespace"]').fill(String(namespace.id));
    await submitForm(mapFilter);

    await expect(mapFilter.locator('input[name="user"]')).toHaveValue(String(fixtures.user.id));
    await expect(mapFilter.locator('input[name="user_namespace"]')).toHaveValue(String(namespace.id));
    await expect(userNamespaceMapRow(page, stableMap.id)).toContainText(fixtures.user.username);
    await expect(userNamespaceMapRow(page, stableMap.id)).toContainText(String(namespace.id));
    await expect(userNamespaceMapRow(page, stableMap.id)).toContainText(stableMap.label);

    await gotoUserNamespaceMap(page, stableMap.id, stableMap.label);
    await expect(
      formByAction(page, `action=map_edit&id=${stableMap.id}`).locator('input[name="user_namespace"]'),
    ).toHaveValue(String(namespace.id));
    await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: 0,
      nsId: 0,
      count: namespace.size,
    });

    const temporaryMapId = await createUserNamespaceMap(page, temporaryLabel, {
      userNamespaceId: namespace.id,
    });
    await renameUserNamespaceMap(page, temporaryMapId, renamedLabel);

    await addMapEntries(page, {
      kind: 'both',
      ...addedEntry,
    });
    await mapEntryRowByValues(page, {
      kind: 'uid',
      ...addedEntry,
    });
    await mapEntryRowByValues(page, {
      kind: 'gid',
      ...addedEntry,
    });

    const uidRow = await mapEntryRowByValues(page, {
      kind: 'uid',
      ...addedEntry,
    });
    await uidRow.locator('input[name="count[]"]').fill(String(addedEntry.count + 1));
    await saveMapEntries(page);
    await gotoUserNamespaceMap(page, temporaryMapId, renamedLabel);
    await mapEntryRowByValues(page, {
      kind: 'uid',
      vpsId: addedEntry.vpsId,
      nsId: addedEntry.nsId,
      count: addedEntry.count + 1,
    });

    await deleteMapEntry(page, {
      kind: 'uid',
      vpsId: addedEntry.vpsId,
      nsId: addedEntry.nsId,
      count: addedEntry.count + 1,
    });
    await gotoUserNamespaceMap(page, temporaryMapId, renamedLabel);
    await expectNoMapEntryByValues(page, {
      kind: 'uid',
      vpsId: addedEntry.vpsId,
      nsId: addedEntry.nsId,
      count: addedEntry.count + 1,
    });
    await mapEntryRowByValues(page, {
      kind: 'gid',
      ...addedEntry,
    });

    await deleteMapEntry(page, {
      kind: 'gid',
      ...addedEntry,
    });
    await deleteUserNamespaceMap(page, temporaryMapId);
    await expect(userNamespaceMapRow(page, temporaryMapId)).toHaveCount(0);

    await logout(page, fixtures.admin.username);
  });
});
