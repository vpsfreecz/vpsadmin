const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  expectNotification,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  advisoryIdFromUrl,
  applyNodeStatusDefaults,
  content,
  fillAdvisoryTextFields,
  fillUpdateTextFields,
  formByAction,
  gotoAdvisory,
  heading,
  linkIdFromForm,
  rowWithText,
  setNodeStatus,
  submitConfirmProtectedForm,
  updateIdFromRow,
} = require('../lib/pages/security-advisory.cjs');
const { setCheckboxIfPresent } = require('../lib/pages/support.cjs');

const fixtures = readFixtures();
const advisories = fixtures.securityAdvisories;

function requireSecurityAdvisoryFixtures() {
  if (
    !advisories
    || !Array.isArray(advisories.nodes)
    || advisories.nodes.length === 0
    || !advisories.publishedAffected
    || !advisories.publishedNotAffected
    || !advisories.draftHidden
    || !advisories.uiCreate
    || !advisories.uiCreate.editedPublishedAt
  ) {
    throw new Error('security advisory coverage requires fixtures.securityAdvisories');
  }

  return advisories;
}

async function expectAdvisoryRow(page, advisory) {
  const row = rowWithText(page, advisory.summary);
  await expect(row).toBeVisible();
  await expect(row).toContainText(advisory.name);

  for (const cve of advisory.cves) {
    await expect(row).toContainText(cve);
  }

  return row;
}

async function expectAdvisoryAbsent(page, advisory) {
  await expect(content(page)).not.toContainText(advisory.name);
  await expect(content(page)).not.toContainText(advisory.summary);
}

function expectedAdvisoryTime(value) {
  const [date, time] = String(value).split(' ');
  const parts = time.split(':');

  while (parts.length < 3) {
    parts.push('00');
  }

  return `${date} ${parts.slice(0, 3).join(':')} UTC`;
}

async function expectAdvisoryDetail(page, advisory, options = {}) {
  await expect(heading(page)).toContainText(`Security advisory #${advisory.id}`);
  await expect(content(page)).toContainText(advisory.name);
  await expect(content(page)).toContainText(advisory.summary);
  await expect(content(page)).toContainText(advisory.description);
  await expect(content(page)).toContainText(advisory.response);

  for (const cve of advisory.cves) {
    await expect(content(page)).toContainText(cve);
  }

  if (options.publicLanguageLabels) {
    await expect(content(page)).toContainText(`English: ${advisory.summary}`);
  }
}

test.describe('security advisory public browser coverage', () => {
  test('anonymous pages show only published advisories', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();

    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(content(page)).toContainText('Recent security advisories');
    await expect(content(page)).toContainText(s.publishedAffected.summary);
    await expect(content(page)).toContainText(s.publishedNotAffected.summary);
    await expectAdvisoryAbsent(page, s.draftHidden);

    await gotoAdvisory(page, 'list');
    await expect(content(page)).toContainText('Security advisories');
    await expectAdvisoryRow(page, s.publishedAffected);
    await expectAdvisoryRow(page, s.publishedNotAffected);
    await expectAdvisoryAbsent(page, s.draftHidden);

    await gotoAdvisory(page, 'show', { id: s.publishedAffected.id });
    await expectAdvisoryDetail(page, s.publishedAffected, {
      publicLanguageLabels: true,
    });

    await gotoAdvisory(page, 'show', { id: s.draftHidden.id });
    await expectAdvisoryAbsent(page, s.draftHidden);
  });
});

test.describe('security advisory user browser coverage', () => {
  test('user filters, affected status, and VPS links are visible', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const affected = s.publishedAffected;
    const notAffected = s.publishedNotAffected;
    const draft = s.draftHidden;

    await login(page, fixtures.user);
    await gotoAdvisory(page, 'list', {
      affected: 'yes',
      vps: affected.vpsId,
    });
    await expect(content(page)).toContainText('Security advisories');
    await expectAdvisoryRow(page, affected);
    await expectAdvisoryAbsent(page, notAffected);
    await expectAdvisoryAbsent(page, draft);

    await gotoAdvisory(page, 'show', { id: affected.id });
    await expectAdvisoryDetail(page, affected);
    await expect(content(page)).toContainText('Your affected VPS');
    await expect(content(page)).toContainText(affected.vpsHostname);
    await expect(content(page)).not.toContainText('Edit advisory');
    await expect(content(page)).not.toContainText('Node statuses');
    await expect(content(page)).not.toContainText('Post update');

    await gotoAdvisory(page, 'show', { id: notAffected.id });
    await expectAdvisoryDetail(page, notAffected);
    await expect(content(page)).toContainText(
      'Your VPS were not affected by this advisory.',
    );

    await gotoAdvisory(page, 'show', { id: draft.id });
    await expectAdvisoryAbsent(page, draft);

    await page.goto(`/?page=adminvps&action=info&veid=${affected.vpsId}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(
      page.locator(
        `#aside a[href="?page=security_advisory&action=list&vps=${affected.vpsId}"]`,
      ),
    ).toBeVisible();

    await logout(page, fixtures.user.username);
  });
});

test.describe('security advisory admin browser workflow', () => {
  test.describe.configure({ mode: 'serial' });

  let advisoryId = null;
  let updateId = null;

  test.beforeEach(async ({ page }) => {
    requireSecurityAdvisoryFixtures();
    await login(page, fixtures.admin);
  });

  test.afterEach(async ({ page }) => {
    await logout(page, fixtures.admin.username);
  });

  test('creates a draft advisory with CVEs and node status defaults', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'new');
    await expect(heading(page)).toContainText('New security advisory');

    const form = formByAction(page, 'action=new');
    await expect(form).toBeVisible();
    await fillAdvisoryTextFields(form, {
      publishedAt: ui.publishedAt,
      cves: ui.cves,
      name: ui.name,
      summary: ui.summary,
      description: ui.description,
      response: ui.response,
    });
    await applyNodeStatusDefaults(
      form,
      {
        state: 'mitigated',
        vulnerableUntil: ui.vulnerableUntil,
        mitigatedSince: ui.mitigatedSince,
        note: ui.nodeNote,
      },
      s.nodes,
    );
    await submitForm(form, 'Create draft');

    advisoryId = advisoryIdFromUrl(page);
    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('draft');
    await expect(content(page)).toContainText(ui.name);
    await expect(content(page)).toContainText(ui.summary);
    await expect(content(page)).toContainText(expectedAdvisoryTime(ui.publishedAt));
    await expect(content(page)).toContainText(ui.nodeNote);

    for (const cve of ui.cves) {
      await expect(content(page)).toContainText(cve);
    }
  });

  test('edits staged publication time before publishing', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'edit', { id: advisoryId });
    const form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="published_at"]')).toHaveValue(ui.publishedAt);
    await fillAdvisoryTextFields(form, {
      publishedAt: ui.editedPublishedAt,
    });
    await submitForm(form, 'Save');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('draft');
    await expect(content(page)).toContainText(expectedAdvisoryTime(ui.editedPublishedAt));
  });

  test('edits node statuses and restores publishable defaults', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;
    const node = s.nodes[0];

    await gotoAdvisory(page, 'nodes', { id: advisoryId });
    let form = formByAction(page, `action=nodes&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await setNodeStatus(form, node.id, {
      state: 'not_affected',
      vulnerableUntil: '',
      mitigatedSince: '',
      note: ui.notAffectedNote,
    });
    await submitForm(form, 'Save node statuses');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('not affected');
    await expect(content(page)).toContainText(ui.notAffectedNote);

    await gotoAdvisory(page, 'nodes', { id: advisoryId });
    form = formByAction(page, `action=nodes&id=${advisoryId}`);
    await applyNodeStatusDefaults(
      form,
      {
        state: 'mitigated',
        vulnerableUntil: ui.vulnerableUntil,
        mitigatedSince: ui.mitigatedSince,
        note: ui.nodeNote,
      },
      s.nodes,
    );
    await submitForm(form, 'Save node statuses');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('mitigated');
    await expect(content(page)).toContainText(ui.nodeNote);
  });

  test('edits draft advisory CVEs, name, and translated text', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'edit', { id: advisoryId });
    const form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await fillAdvisoryTextFields(form, {
      cves: ui.editedCves,
      name: ui.editedName,
      summary: ui.editedSummary,
      description: ui.editedDescription,
      response: ui.editedResponse,
    });
    await submitForm(form, 'Save');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText(ui.editedName);
    await expect(content(page)).toContainText(ui.editedSummary);
    await expect(content(page)).toContainText(ui.editedDescription);
    await expect(content(page)).toContainText(ui.editedResponse);
    await expect(content(page)).toContainText(expectedAdvisoryTime(ui.editedPublishedAt));

    for (const cve of ui.editedCves) {
      await expect(content(page)).toContainText(cve);
    }
  });

  test('publishes with mail disabled and editable published time', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'show', { id: advisoryId });
    const form = formByAction(page, `action=publish&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="send_mail"]')).not.toBeChecked();
    await expect(form.locator('input[name="published_at"]')).toHaveValue(ui.editedPublishedAt);
    await setCheckboxIfPresent(form, 'send_mail', false);
    await submitForm(form, 'Publish');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('published');
    await expect(content(page)).toContainText(ui.editedName);
    await expect(content(page)).toContainText(expectedAdvisoryTime(ui.editedPublishedAt));
  });

  test('posts, edits, and deletes an advisory update', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'update', { id: advisoryId });
    let form = formByAction(page, `action=update&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="send_mail"]')).not.toBeChecked();
    await expect(form.locator('input[name="published_at"]')).toHaveValue(ui.editedPublishedAt);
    await fillUpdateTextFields(form, {
      summary: ui.updateSummary,
      message: ui.updateMessage,
    });
    await setCheckboxIfPresent(form, 'send_mail', false);
    await submitForm(form, 'Post update');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText(ui.updateSummary);
    await expect(content(page)).toContainText(ui.updateMessage);

    const updateRow = rowWithText(page, ui.updateSummary);
    updateId = await updateIdFromRow(page, updateRow);

    await gotoAdvisory(page, 'edit_update', {
      id: advisoryId,
      update: updateId,
    });
    form = formByAction(page, `action=edit_update&id=${advisoryId}&update=${updateId}`);
    await expect(form).toBeVisible();
    await fillUpdateTextFields(form, {
      summary: ui.editedUpdateSummary,
      message: ui.editedUpdateMessage,
    });
    await submitForm(form, 'Save');
    await expectNotification(page, 'Update saved');

    await gotoAdvisory(page, 'show', { id: advisoryId });
    await expect(content(page)).toContainText(ui.editedUpdateSummary);
    await expect(content(page)).toContainText(ui.editedUpdateMessage);

    const editedRow = rowWithText(page, ui.editedUpdateSummary);
    await expect(editedRow).toBeVisible();
    const deleteForm = formByAction(page, 'action=delete_update');
    await expect(deleteForm).toHaveAttribute('action', new RegExp(`update=${updateId}`));
    await expect(deleteForm).toBeVisible();
    await submitConfirmProtectedForm(page, deleteForm);
    await expectNotification(page, 'Update deleted');
    await expect(rowWithText(page, ui.editedUpdateSummary)).toHaveCount(0);
    await expect(content(page)).toContainText('No updates posted.');
  });

  test('links and unlinks an outage from advisory detail', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;
    const outage = ui.outage;

    await gotoAdvisory(page, 'show', { id: advisoryId });
    const form = formByAction(page, `action=link_outage&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await form.locator('input[name="outage"]').fill(String(outage.id));
    await submitForm(form, 'Link outage');

    const row = rowWithText(page, outage.summary);
    await expect(row).toBeVisible();
    await expect(row).toContainText(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/);
    await expect(row).toContainText(outage.typeText);
    await expect(row).toContainText(outage.impactText);
    await expect(row.locator(`a[href*="page=outage&action=show&id=${outage.id}"]`))
      .toBeVisible();

    const unlinkForm = row.locator('form[action*="action=unlink_outage"]').first();
    await expect(unlinkForm).toBeVisible();
    expect(await linkIdFromForm(page, unlinkForm)).toMatch(/^\d+$/);
    await submitConfirmProtectedForm(page, unlinkForm);
    await expect(rowWithText(page, outage.summary)).toHaveCount(0);
    await expect(content(page)).toContainText('No outages linked.');
  });

  test('links two advisories from outage detail and unlinks them there', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;
    const outage = ui.outage;
    const seeded = s.publishedNotAffected;

    await page.goto(`/?page=outage&action=show&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });

    const form = formByAction(page, `action=link_security_advisory&id=${outage.id}`);
    await expect(form).toBeVisible();
    await form
      .locator('select[name="security_advisory[]"]')
      .selectOption([String(advisoryId), String(seeded.id)]);
    await submitForm(form, 'Link');

    let cvesRow = rowWithText(page, 'CVEs');
    await expect(cvesRow).toContainText(ui.editedName);
    await expect(cvesRow).toContainText(seeded.name);

    for (const cve of ui.editedCves.concat(seeded.cves)) {
      await expect(cvesRow).toContainText(cve);
    }

    const createdUnlinkForm = cvesRow
      .locator(
        `xpath=.//a[contains(@href, "page=security_advisory&action=show&id=${advisoryId}")]/following-sibling::form[contains(@action, "action=unlink_security_advisory")][1]`,
      )
      .first();
    await expect(createdUnlinkForm).toBeVisible();
    await submitConfirmProtectedForm(page, createdUnlinkForm);

    cvesRow = rowWithText(page, 'CVEs');
    await expect(cvesRow).toContainText(seeded.name);
    await expect(cvesRow).not.toContainText(ui.editedName);

    const seededUnlinkForm = cvesRow
      .locator(
        `xpath=.//a[contains(@href, "page=security_advisory&action=show&id=${seeded.id}")]/following-sibling::form[contains(@action, "action=unlink_security_advisory")][1]`,
      )
      .first();
    await expect(seededUnlinkForm).toBeVisible();
    await submitConfirmProtectedForm(page, seededUnlinkForm);

    cvesRow = rowWithText(page, 'CVEs');
    await expect(cvesRow).toContainText('-');
    await expect(cvesRow).not.toContainText(seeded.name);
  });
});
