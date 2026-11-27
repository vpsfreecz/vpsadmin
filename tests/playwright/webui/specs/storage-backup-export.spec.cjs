const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  formByAction,
  submitForm,
  visibleTransactionChainIds,
  waitForTransactionChainsSettled,
} = require('../lib/pages/webui.cjs');
const {
  actionLink,
  expectStorageNotification: expectNotification,
  openDatasetEdit,
  rowWithText,
  setCheckbox,
  setSelectIfPresent,
  submitExportSettings,
  submitExportStatus,
} = require('../lib/pages/storage.cjs');

const fixtures = readFixtures();
const storage = fixtures.storage;

function requireStorageFixtures() {
  if (!storage || !storage.datasets || !storage.exports || !storage.vps) {
    throw new Error('storage-backup-export requires fixtures.storage');
  }

  return storage;
}

function returnToBackup() {
  return encodeURIComponent('/?page=backup');
}

async function currentTransactionChainIds(page) {
  return new Set(await visibleTransactionChainIds(page));
}

async function waitForNewTransactionChains(page, beforeIds) {
  const chainIds = (await visibleTransactionChainIds(page))
    .filter((id) => !beforeIds.has(id));

  if (chainIds.length > 0) {
    await waitForTransactionChainsSettled(page, { chainIds });
  }
}

async function runWithTransactionWait(page, callback) {
  const beforeIds = await currentTransactionChainIds(page);
  await callback();
  await waitForNewTransactionChains(page, beforeIds);
}

async function confirmCurrentForm(page, actionPart, button, notification) {
  const beforeIds = await currentTransactionChainIds(page);
  const form = formByAction(page, actionPart);
  await expect(form).toBeVisible();
  await setCheckbox(form, 'confirm', true, { required: true });
  await submitForm(form, button);
  await expectNotification(page, notification);
  await waitForNewTransactionChains(page, beforeIds);
}

async function submitSnapshotRestore(page, dataset, snapshot, listUrl = '/?page=backup&action=nas') {
  await page.goto(listUrl, { waitUntil: 'domcontentloaded' });

  const form = formByAction(page, `action=restore&dataset=${dataset.id}`);
  await expect(form).toBeVisible();
  await form
    .locator(`input[name="restore_snapshot"][value="${snapshot.id}"]`)
    .check({ force: true });
  await submitForm(form, 'Restore');

  await expect(page.locator('#content-in')).toContainText('Confirm the restoration');
  await confirmCurrentForm(page, `action=restore&dataset=${dataset.id}`, 'Restore dataset', 'Restoration scheduled');
}

async function submitSnapshotDownload(page, dataset, snapshot) {
  await page.goto(
    `/?page=backup&action=download&dataset=${dataset.id}&snapshot=${snapshot.id}&return=${returnToBackup()}`,
    { waitUntil: 'domcontentloaded' },
  );

  const form = formByAction(page, `action=download&dataset=${dataset.id}`);
  await expect(form).toBeVisible();
  await form.locator('select[name="format"]').selectOption('archive');
  await setCheckbox(form, 'confirm', true, { required: true });
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Download snapshot');
  await expectNotification(page, 'Download of snapshot of');
  await waitForNewTransactionChains(page, beforeIds);
}

async function submitSnapshotDestroy(page, dataset, snapshot) {
  await page.goto(
    `/?page=backup&action=snapshot_destroy&dataset=${dataset.id}&snapshot=${snapshot.id}&return=${returnToBackup()}`,
    { waitUntil: 'domcontentloaded' },
  );

  await expect(page.locator('#content-in')).toContainText('Confirm snapshot deletion');
  await confirmCurrentForm(page, `action=snapshot_destroy&dataset=${dataset.id}`, 'Delete', 'Snapshot deleted');
}

async function createExportFrom(page, params) {
  const search = new URLSearchParams({
    page: 'export',
    action: 'create',
    dataset: String(params.dataset.id),
  });

  if (params.snapshot) {
    search.set('snapshot', String(params.snapshot.id));
  }

  await page.goto(`/?${search.toString()}`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Create NFS export');

  const form = formByAction(page, `action=create&dataset=${params.dataset.id}`);
  await expect(form).toBeVisible();
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Create');
  await expectNotification(page, 'Export created');
  await waitForNewTransactionChains(page, beforeIds);
  await expect(page).toHaveURL(/page=export.*action=edit.*export=/);
}

async function createMountFromVpsDetail(page, vps) {
  await page.goto(`/?page=adminvps&action=info&veid=${vps.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await actionLink(page, 'mount', {
    vps: vps.id,
    dataset: vps.childDatasetId,
  }).click();

  const form = formByAction(page, `action=mount&vps=${vps.id}`);
  await expect(form).toBeVisible();
  await form.locator('input[name="mountpoint"]').fill(`/mnt/${vps.hostname}`);
  await setSelectIfPresent(form, 'mode', 'rw');
  await setSelectIfPresent(form, 'on_start_fail', 'skip');
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Save');
  await expectNotification(page, 'Mount created');
  await waitForNewTransactionChains(page, beforeIds);
}

async function editMount(page, mount, onStartFail) {
  await page.goto(
    `/?page=dataset&action=mount_edit&vps=${mount.vpsId}&id=${mount.id}&return=%2F%3Fpage%3Dadminvps`,
    { waitUntil: 'domcontentloaded' },
  );

  const form = formByAction(page, `action=mount_edit&vps=${mount.vpsId}`);
  await expect(form).toBeVisible();
  await form.locator('select[name="on_start_fail"]').selectOption(onStartFail);
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Save');
  await expectNotification(page, 'Changes saved');
  await waitForNewTransactionChains(page, beforeIds);
}

async function destroyMount(page, mount) {
  await page.goto(
    `/?page=dataset&action=mount_destroy&vps=${mount.vpsId}&id=${mount.id}&return=%2F%3Fpage%3Dadminvps`,
    { waitUntil: 'domcontentloaded' },
  );
  await confirmCurrentForm(page, `action=mount_destroy&vps=${mount.vpsId}`, 'Remove mount', 'Mount removed');
}

async function toggleMount(page, mount) {
  await page.goto(`/?page=adminvps&action=info&veid=${mount.vpsId}`, {
    waitUntil: 'domcontentloaded',
  });
  const beforeIds = await currentTransactionChainIds(page);
  await actionLink(page, 'mount_toggle', {
    vps: mount.vpsId,
    id: mount.id,
  }).click();
  await expectNotification(page, 'Mount disabled');
  await waitForNewTransactionChains(page, beforeIds);
}

async function addExportHost(page, exportFixture, ipAddress) {
  await page.goto(`/?page=export&action=add_host&export=${exportFixture.id}`, {
    waitUntil: 'domcontentloaded',
  });

  const form = formByAction(page, `action=add_host&export=${exportFixture.id}`);
  await expect(form).toBeVisible();
  await form.locator('select[name="ip_address"]').selectOption(String(ipAddress.id));
  await setCheckbox(form, 'rw', true);
  await setCheckbox(form, 'sync', true);
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Save');
  await expectNotification(page, 'Host added');
  await waitForNewTransactionChains(page, beforeIds);
}

async function editExportHost(page, exportFixture, options = {}) {
  await page.goto(
    `/?page=export&action=edit_host&export=${exportFixture.id}&host=${exportFixture.hostId}`,
    { waitUntil: 'domcontentloaded' },
  );

  const form = formByAction(page, `action=edit_host&export=${exportFixture.id}`);
  await expect(form).toBeVisible();
  await setCheckbox(form, 'rw', options.rw ?? false);
  await setCheckbox(form, 'root_squash', options.rootSquash ?? true);
  const beforeIds = await currentTransactionChainIds(page);
  await submitForm(form, 'Save');
  await expectNotification(page, 'Host settings updated');
  await waitForNewTransactionChains(page, beforeIds);
}

async function deleteExportHost(page, exportFixture) {
  await page.goto(`/?page=export&action=edit&export=${exportFixture.id}`, {
    waitUntil: 'domcontentloaded',
  });
  const beforeIds = await currentTransactionChainIds(page);
  await actionLink(page, 'del_host', {
    export: exportFixture.id,
    host: exportFixture.hostId,
  }).click();
  await expectNotification(page, 'Host removed');
  await waitForNewTransactionChains(page, beforeIds);
}

test.describe.serial('storage, backup, dataset, and export browser coverage', () => {
  test('user backup lists and snapshot/download actions are wired', async ({ page }) => {
    const s = requireStorageFixtures();

    await login(page, fixtures.user);

    await page.goto(`/?page=adminvps&action=info&veid=${s.vps.backup.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(s.vps.backup.childDatasetName);
    await expect(page.locator('#content-in')).toContainText('Mounts');

    await page.goto('/?page=backup&action=vps', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('VPS Backups');
    await expect(page.locator('form[name="backup-filter"]')).toHaveCount(0);
    await expect(page.locator('#content-in')).toContainText(s.vps.backup.hostname);
    await expect(page.locator('#content-in')).toContainText(s.snapshots.vps_backup.label);

    await page.goto('/?page=backup&action=nas', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('NAS Backups');
    await expect(page.locator('#content-in')).toContainText(s.datasets.nas_list.name);
    await expect(page.locator('#content-in')).toContainText(s.snapshots.nas_list.label);
    await expect(page.locator('#content-in')).toContainText('Export to mount');

    await page.goto('/?page=backup&action=downloads', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('Downloads');
    await expect(rowWithText(page, s.downloads.show.fileName)).toBeVisible();

    await page.goto(`/?page=backup&action=download_link&id=${s.downloads.show.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(s.downloads.show.fileName);
    await expect(page.locator('#content-in a', { hasText: 'download' })).toBeVisible();

    await page.goto(
      `/?page=backup&action=snapshot&dataset=${s.datasets.snapshot_create.id}&return=${returnToBackup()}`,
      { waitUntil: 'domcontentloaded' },
    );
    const snapshotForm = formByAction(page, 'action=snapshot_create');
    await snapshotForm.locator('input[name="label"]').fill('Webui user snapshot create');
    const beforeIds = await currentTransactionChainIds(page);
    await submitForm(snapshotForm, 'Create snapshot');
    await expectNotification(page, 'Snapshot creation scheduled');
    await waitForNewTransactionChains(page, beforeIds);

    await submitSnapshotRestore(page, s.datasets.restore, s.snapshots.restore);
    await submitSnapshotDownload(page, s.datasets.download_create, s.snapshots.download_create);
    await submitSnapshotDestroy(page, s.datasets.snapshot_destroy, s.snapshots.snapshot_destroy);

    await page.goto(`/?page=backup&action=download_destroy&id=${s.downloads.destroy.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await confirmCurrentForm(page, 'action=download_destroy', 'Destroy download link', 'Download link destroyed');

    await logout(page, fixtures.user.username);
  });

  test('user dataset mounts and public exports submit expected forms', async ({ page }) => {
    const s = requireStorageFixtures();

    await login(page, fixtures.user);

    await openDatasetEdit(page, s.datasets.user_edit.id, 'primary');
    const userEditForm = formByAction(
      page,
      `action=edit&role=primary&id=${s.datasets.user_edit.id}`,
    );
    await expect(page.locator('a[href*="action=disable_backups"]')).toHaveCount(0);
    await expect(formByAction(page, 'action=disable_backups')).toHaveCount(0);
    await expect(formByAction(page, 'action=remove_snapshots')).toHaveCount(0);
    await expect(formByAction(page, 'action=plan_add')).toContainText('Existing snapshots remain on primary and backup pools.');
    await expect(userEditForm.locator('input[name="admin_override"]')).toHaveCount(0);
    await expect(userEditForm.locator('input[name="inherit_atime"]')).toHaveCount(1);
    await expect(userEditForm.locator('input[name="atime"]')).toHaveCount(1);
    await page.goto(`/?page=dataset&action=disable_backups&id=${s.datasets.user_edit.id}`, { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content')).toContainText('Disabling backups is unavailable');
    await expect(formByAction(page, 'action=disable_backups')).toHaveCount(0);
    await page.goto(`/?page=dataset&action=remove_snapshots&id=${s.datasets.user_edit.id}`, { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content')).toContainText('Snapshot removal is unavailable');
    await expect(formByAction(page, 'action=remove_snapshots')).toHaveCount(0);

    await editMount(page, s.mounts.user_edit, 'skip');
    await toggleMount(page, s.mounts.user_toggle);
    await destroyMount(page, s.mounts.user_destroy);
    await createMountFromVpsDetail(page, s.vps.user_mount_create);

    await page.goto('/?page=export', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in h1')).toContainText('NFS exports');
    await expect(page.locator('form[name="export-filter"]')).toHaveCount(0);
    await expect(rowWithText(page, s.exports.list.datasetName)).toBeVisible();

    await page.goto('/?page=export&action=export_dataset', {
      waitUntil: 'domcontentloaded',
    });
    const selectorForm = formByAction(page, 'action=export_dataset');
    await selectorForm.locator('select[name="dataset"]').selectOption(String(s.datasets.export_selector.id));
    await submitForm(selectorForm, 'Continue');
    await expect(page.locator('#content-in')).toContainText('Create NFS export');
    await expect(page.locator('#content-in')).toContainText(s.datasets.export_selector.name);

    await createExportFrom(page, { dataset: s.datasets.export_create });
    await createExportFrom(page, {
      dataset: s.datasets.export_snapshot,
      snapshot: s.snapshots.export_snapshot,
    });
    await runWithTransactionWait(page, async () => submitExportSettings(page, s.exports.edit.id, {
      checkboxes: {
        rw: false,
        root_squash: true,
      },
    }));
    await runWithTransactionWait(page, async () => submitExportStatus(
      page,
      s.exports.enable.id,
      'enable',
      'Start',
      'Export activated',
    ));
    await runWithTransactionWait(page, async () => submitExportStatus(
      page,
      s.exports.disable.id,
      'disable',
      'Stop',
      'Export deactivated',
    ));

    await page.goto(`/?page=export&action=destroy&export=${s.exports.destroy.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await confirmCurrentForm(page, 'action=destroy', 'Delete export', 'Export deleted');

    await addExportHost(page, s.exports.host_add, s.ipAddresses.assignedHost);
    await editExportHost(page, s.exports.host_edit);
    await deleteExportHost(page, s.exports.host_delete);

    await logout(page, fixtures.user.username);
  });

  test('administrator backup cleanup confirmation is scoped and localized', async ({ page }) => {
    const s = requireStorageFixtures();
    await login(page, fixtures.admin);
    const variants = [
      ['en_US.utf8', 'Back up existing snapshots first', 'Existing snapshots remain on primary and backup pools.', 'This removes the selected datasets from all backup plans and deletes their local snapshots. Backups are preserved. Re-enabling backups will require a full transfer.', 'Confirm'],
      ['cs_CZ.utf8', 'Nejprve zálohovat existující snapshoty', 'Existující snapshoty zůstanou na primárních i zálohovacích poolech.', 'Tato akce odebere vybrané datasety ze všech zálohovacích plánů a odstraní jejich lokální snapshoty. Zálohy zůstanou zachované. Opětovné zapnutí zálohování bude vyžadovat úplný přenos.', 'Potvrdit'],
    ];
    for (const [locale, checkboxLabel, planHelp, paragraph, confirmLabel] of variants) {
      await openDatasetEdit(page, s.datasets.user_edit.id, 'primary');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
        page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`).click(),
      ]);
      await expect(formByAction(page, 'action=plan_add')).toContainText(planHelp);
      await expect(page.locator('a[href*="action=disable_backups"]')).toHaveCount(0);
      const form = formByAction(page, 'action=disable_backups');
      await expect(form).toBeVisible();
      expect(await form.evaluate(el => el.previousElementSibling.previousElementSibling.getAttribute('action'))).toContain('action=plan_add');
      await expect(form).toHaveAttribute('method', 'post');
      const recursive = form.locator('input[type="checkbox"][name="recursive"]');
      const backupFirst = form.locator('input[type="checkbox"][name="backup_first"]');
      await expect(recursive).not.toBeChecked();
      await expect(backupFirst).toBeChecked();
      await expect(form).toContainText(checkboxLabel);
      await expect(form.locator('p')).toHaveCount(1);
      await expect(form.locator('p')).toHaveText(paragraph);
      await expect(form.locator('ul')).toHaveCount(0);
      expect(await form.locator('tr').evaluateAll(rows => rows.filter(row => row.cells.length > 0).every(row => [...row.cells].reduce((width, cell) => width + cell.colSpan, 0) === 2))).toBe(true);
      const confirm = form.locator('input[name="confirm"]');
      await expect(confirm).not.toBeChecked();
      await expect(confirm).toHaveAttribute('required', '');
      expect(await confirm.evaluate(el => el.validity.valueMissing)).toBe(true);
      await expect(form.locator('input[name="csrf_token"]')).toHaveCount(1);
      await expect(form.locator('label[for="disable-backups-confirm"]')).toHaveText(confirmLabel);
      expect(new URL(await form.getAttribute('action'), page.url()).searchParams.get('id')).toBe(String(s.datasets.user_edit.id));
      await recursive.check();
      await expect(backupFirst).toBeChecked();
      await backupFirst.uncheck();
      await expect(recursive).toBeChecked();
    }
    await page.goto(`/?page=backup&action=vps&vps=${s.vps.backup.id}`, { waitUntil: 'domcontentloaded' });
    const recursiveLink = page.locator(`a[href*="action=disable_backups"][href*="recursive=1"]`);
    await expect(recursiveLink).toHaveCount(1);
    await recursiveLink.click();
    await expect(formByAction(page, 'action=disable_backups').locator('input[name="recursive"]')).not.toBeChecked();
    // Leave shared destructive fixtures intact; one-call task handling and failure
    // cases have real-client PHPUnit coverage and storage integration coverage.
    await logout(page, fixtures.admin.username);
  });

  test('administrator snapshot removal reviews inventory before a distinct final confirmation', async ({ page }) => {
    const s = requireStorageFixtures();
    await login(page, fixtures.admin);
    const variants = [
      ['en_US.utf8', 'Preview snapshot removal', 'Continue to final confirmation', 'Final confirmation of snapshot removal', 'Back to review'],
      ['cs_CZ.utf8', 'Zobrazit náhled odstranění snapshotů', 'Pokračovat k závěrečnému potvrzení', 'Závěrečné potvrzení odstranění snapshotů', 'Zpět na kontrolu'],
    ];
    const viewports = [{ width: 1280, height: 720 }, { width: 390, height: 844 }];
    const cases = viewports.flatMap((viewport) => variants.map((variant) => [viewport, ...variant]));
    for (const [viewport, locale, previewLabel, continueLabel, finalTitle, backLabel] of cases) {
      await page.setViewportSize(viewport);
      await openDatasetEdit(page, s.datasets.snapshot_create.id, 'primary');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
        page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`).click(),
      ]);
      const options = formByAction(page, 'action=remove_snapshots');
      await expect(options).toBeVisible();
      await expect(options.locator('input[type="checkbox"][name="recursive"]')).not.toBeChecked();
      await expect(options.locator('input[type="checkbox"][name="disable_plans"]')).toBeChecked();
      await submitForm(options, previewLabel);
      const review = page.locator('form').filter({ has: page.locator('input[name="phase"][value="continue"]') });
      await expect(review).toBeVisible();
      await expect(page.locator('#content')).toContainText('Webui user snapshot create');
      await expect(review.locator('input[name="acknowledge"]')).not.toBeChecked();
      await expect(page.locator('input[name="confirm"]')).toHaveCount(0);
      const digest = await review.locator('input[name="manifest_digest"]').inputValue();
      expect(digest).toMatch(/^v1:[a-f0-9]{64}$/);
      await review.locator('input[name="acknowledge"]').check();
      await submitForm(review, continueLabel);
      await expect(page.locator('#content')).toContainText(finalTitle);
      const final = page.locator('form').filter({ has: page.locator('input[name="phase"][value="remove"]') });
      await expect(final.locator('input[name="confirm"]')).not.toBeChecked();
      await expect(final.locator('input[name="confirm"]')).toHaveAttribute('required', '');
      await expect(final.locator('input[name="manifest_digest"]')).toHaveValue(digest);
      await final.getByRole('button', { name: backLabel, exact: true }).click();
      await expect(review).toBeVisible();
      await expect(review.locator('input[name="acknowledge"]')).not.toBeChecked();
      await expect(review.locator('input[name="manifest_digest"]')).toHaveValue(digest);
      // Leave shared destructive fixtures intact; real-client and storage tests
      // cover final submission and actual history deletion/live-file preservation.
    }
    await logout(page, fixtures.admin.username);
  });
});
