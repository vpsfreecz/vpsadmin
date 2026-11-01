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
  expectNodeStatusInputSizes,
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
    || !advisories.retractedHidden
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
    await expectAdvisoryAbsent(page, s.retractedHidden);
    await expect(
      content(page).locator(
        'a[href="?page=security_advisory&action=list"]',
        { hasText: 'View all' },
      ),
    ).toBeVisible();

    await gotoAdvisory(page, 'list');
    await expect(content(page)).toContainText('Security advisories');
    await expectAdvisoryRow(page, s.publishedAffected);
    await expectAdvisoryRow(page, s.publishedNotAffected);
    await expectAdvisoryAbsent(page, s.draftHidden);
    await expectAdvisoryAbsent(page, s.retractedHidden);

    await gotoAdvisory(page, 'list', { state: 'retracted' });
    await expectAdvisoryAbsent(page, s.retractedHidden);

    await gotoAdvisory(page, 'show', { id: s.publishedAffected.id });
    await expectAdvisoryDetail(page, s.publishedAffected, {
      publicLanguageLabels: true,
    });

    await gotoAdvisory(page, 'show', { id: s.draftHidden.id });
    await expectAdvisoryAbsent(page, s.draftHidden);
    await gotoAdvisory(page, 'show', { id: s.retractedHidden.id });
    await expectAdvisoryAbsent(page, s.retractedHidden);
  });
});

test.describe('security advisory user browser coverage', () => {
  test('user filters, affected status, and VPS links are visible', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const affected = s.publishedAffected;
    const notAffected = s.publishedNotAffected;
    const draft = s.draftHidden;
    const retracted = s.retractedHidden;

    await login(page, fixtures.user);
    await gotoAdvisory(page, 'list', {
      affected: 'yes',
      vps: affected.vpsId,
    });
    await expect(content(page)).toContainText('Security advisories');
    await expectAdvisoryRow(page, affected);
    await expectAdvisoryAbsent(page, notAffected);
    await expectAdvisoryAbsent(page, draft);
    await expectAdvisoryAbsent(page, retracted);

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
    await gotoAdvisory(page, 'show', { id: retracted.id });
    await expectAdvisoryAbsent(page, retracted);
    await gotoAdvisory(page, 'list', { state: 'retracted' });
    await expectAdvisoryAbsent(page, retracted);

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
  let originalPublishedAt = null;

  test.beforeEach(async ({ page }) => {
    requireSecurityAdvisoryFixtures();
    await login(page, fixtures.admin);
  });

  test.afterEach(async ({ page }) => {
    await logout(page, fixtures.admin.username);
  });

  test('lists current drafts among published advisories', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();

    await gotoAdvisory(page, 'list');
    await expectAdvisoryRow(page, s.draftHidden);
    await expectAdvisoryRow(page, s.publishedNotAffected);
    await expectAdvisoryRow(page, s.retractedHidden);

    const rowTexts = await content(page).locator('tr').allTextContents();
    const draftIndex = rowTexts.findIndex((text) => text.includes(s.draftHidden.summary));
    const publishedIndex = rowTexts.findIndex(
      (text) => text.includes(s.publishedNotAffected.summary),
    );

    expect(draftIndex).toBeGreaterThanOrEqual(0);
    expect(publishedIndex).toBeGreaterThanOrEqual(0);
    expect(draftIndex).toBeLessThan(publishedIndex);
  });

  test('creates a draft advisory with CVEs and node status defaults', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const ui = s.uiCreate;

    await gotoAdvisory(page, 'new');
    await expect(heading(page)).toContainText('New security advisory');

    const form = formByAction(page, 'action=new');
    await expect(form).toBeVisible();
    await expectNodeStatusInputSizes(form, s.nodes);
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
        notes: ui.nodeNotes,
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
    await expect(content(page)).toContainText(ui.nodeNotes.en);

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
    await expect(form.locator('input[name="published_at"]')).toHaveValue(`${ui.publishedAt}:00`);
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
    await expectNodeStatusInputSizes(form, s.nodes);
    await setNodeStatus(form, node.id, {
      state: 'not_affected',
      vulnerableUntil: '',
      mitigatedSince: '',
      notes: ui.notAffectedNotes,
    });
    await submitForm(form, 'Save node statuses');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('not affected');
    await expect(content(page)).toContainText(ui.notAffectedNotes.en);

    await gotoAdvisory(page, 'nodes', { id: advisoryId });
    form = formByAction(page, `action=nodes&id=${advisoryId}`);
    await expect(form.locator(`[name="node_${node.id}_vulnerable_until"]`)).toHaveValue('');
    await expect(form.locator(`[name="node_${node.id}_mitigated_since"]`)).toHaveValue('');
    await applyNodeStatusDefaults(
      form,
      {
        state: 'mitigated',
        vulnerableUntil: ui.vulnerableUntil,
        mitigatedSince: ui.mitigatedSince,
        notes: ui.nodeNotes,
      },
      s.nodes,
    );
    await submitForm(form, 'Save node statuses');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('mitigated');
    await expect(content(page)).toContainText(ui.nodeNotes.en);
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
    const staleEditPage = await page.context().newPage();
    const staleNodesPage = await page.context().newPage();
    await gotoAdvisory(staleEditPage, 'edit', { id: advisoryId });
    await gotoAdvisory(staleNodesPage, 'nodes', { id: advisoryId });
    const staleEdit = formByAction(staleEditPage, `action=edit&id=${advisoryId}`);
    const staleNodes = formByAction(staleNodesPage, `action=nodes&id=${advisoryId}`);
    const revision = await staleEdit.locator('[name="expected_content_revision"]').inputValue();

    await gotoAdvisory(page, 'show', { id: advisoryId });
    const form = formByAction(page, `action=publish&id=${advisoryId}`);
    await expect(form).toBeVisible();
    await expect(
      form.locator('input[type="hidden"][name="expected_content_revision"]'),
    ).toHaveCount(1);
    const publishedAtRow = form
      .locator('input[name="published_at"]')
      .locator('xpath=ancestor::tr');
    await expect(publishedAtRow.locator(':scope > td')).toHaveCount(3);
    await expect(publishedAtRow.locator(':scope > td').first()).toHaveText(
      'Published at:',
    );
    await expect(form.locator('input[name="send_mail"]')).not.toBeChecked();
    await expect(form.locator('input[name="published_at"]')).toHaveValue(ui.editedPublishedAt);
    originalPublishedAt = `${ui.editedPublishedAt}:37`;
    await form.locator('input[name="published_at"]').fill(originalPublishedAt);
    await setCheckboxIfPresent(form, 'send_mail', false);
    await submitForm(form, 'Publish');

    await expect(heading(page)).toContainText(`Security advisory #${advisoryId}`);
    await expect(content(page)).toContainText('published');
    await expect(content(page)).toContainText(ui.editedName);
    await expect(content(page)).toContainText(expectedAdvisoryTime(originalPublishedAt));

    for (const [stalePage, staleForm, button] of [
      [staleEditPage, staleEdit, 'Save'],
      [staleNodesPage, staleNodes, 'Save node statuses'],
    ]) {
      await submitForm(staleForm, button);
      await expectNotification(stalePage, 'Update failed');
      await expect(staleForm.locator('[name="expected_state"]')).toHaveValue('draft');
      await expect(staleForm.locator('[name="expected_content_revision"]')).toHaveValue(revision);
      await submitForm(staleForm, button);
      await expectNotification(stalePage, 'Update failed');
      await stalePage.close();
    }
  });

  test('corrects published original text without changing publication or adding an update', async ({ page }) => {
    const ui = requireSecurityAdvisoryFixtures().uiCreate;
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    const form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form.locator('[name="published_at"]')).toHaveValue(originalPublishedAt);
    await expect(form.locator('[name="cves"]')).toHaveValue(ui.editedCves.join(', '));
    await expect(form.locator('[name="expected_state"]')).toHaveValue('published');
    await fillAdvisoryTextFields(form, {
      name: `${ui.editedName} corrected`,
      summary: `${ui.editedSummary} corrected`,
      description: `${ui.editedDescription} Corrected.`,
      response: `${ui.editedResponse} Corrected.`,
    });
    await submitForm(form, 'Save');
    await expect(content(page)).toContainText(`${ui.editedSummary} corrected`);
    await expect(content(page)).toContainText(`${ui.editedDescription} Corrected.`);
    await expect(content(page)).toContainText(`${ui.editedResponse} Corrected.`);
    await expect(content(page)).toContainText(expectedAdvisoryTime(originalPublishedAt));
    await expect(content(page)).toContainText('No updates posted.');
    for (const cve of ui.editedCves) {
      await expect(content(page)).toContainText(cve);
    }
  });

  test('rejects a stale published correction without refreshing its revision', async ({ page }) => {
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    const form = formByAction(page, `action=edit&id=${advisoryId}`);
    const revision = await form.locator('[name="expected_content_revision"]').inputValue();
    const otherPage = await page.context().newPage();
    await gotoAdvisory(otherPage, 'edit', { id: advisoryId });
    await submitForm(formByAction(otherPage, `action=edit&id=${advisoryId}`), 'Save');
    await submitForm(form, 'Save');
    await expectNotification(page, 'Update failed');
    await expect(form.locator('[name="expected_content_revision"]')).toHaveValue(revision);
    await expect(form.locator('[name="expected_state"]')).toHaveValue('published');
    await otherPage.close();
  });

  test('corrects published node rows and refreshes the affected VPS display', async ({ page, browser, baseURL }) => {
    const s = requireSecurityAdvisoryFixtures();
    const nodeId = s.publishedAffected.nodeId;
    const userContext = await browser.newContext({ baseURL });
    const userPage = await userContext.newPage();
    try {
      await login(userPage, fixtures.user);
      await gotoAdvisory(userPage, 'show', { id: advisoryId });
      await expect(content(userPage)).toContainText(s.publishedAffected.vpsHostname);
      await gotoAdvisory(page, 'nodes', { id: advisoryId });
      let form = formByAction(page, `action=nodes&id=${advisoryId}`);
      await expect(form.locator('[name="expected_state"]')).toHaveValue('published');
      await expect(form.locator(`[name="node_${nodeId}_vulnerable_until"]`)).toHaveValue(s.uiCreate.vulnerableUntil);
      await expect(form.locator(`[name="node_${nodeId}_mitigated_since"]`)).toHaveValue(s.uiCreate.mitigatedSince);
      await setNodeStatus(form, nodeId, { notes: { en: 'Corrected node note', cs: '' } });
      await submitForm(form, 'Save node statuses');
      await gotoAdvisory(page, 'nodes', { id: advisoryId });
      form = formByAction(page, `action=nodes&id=${advisoryId}`);
      await expect(form.locator(`[name="node_${nodeId}_vulnerable_until"]`)).toHaveValue(s.uiCreate.vulnerableUntil);
      await expect(form.locator(`[name="node_${nodeId}_mitigated_since"]`)).toHaveValue(s.uiCreate.mitigatedSince);
      await expect(form.locator(`[name="node_${nodeId}_en_note"]`)).toHaveValue('Corrected node note');
      await expect(form.locator(`[name="node_${nodeId}_cs_note"]`)).toHaveValue('');
      await setNodeStatus(form, nodeId, { state: 'not_affected' });
      await submitForm(form, 'Save node statuses');
      await gotoAdvisory(userPage, 'show', { id: advisoryId });
      await expect(content(userPage)).not.toContainText(s.publishedAffected.vpsHostname);
      await gotoAdvisory(page, 'nodes', { id: advisoryId });
      form = formByAction(page, `action=nodes&id=${advisoryId}`);
      await setNodeStatus(form, nodeId, {
        state: 'mitigated',
        vulnerableUntil: s.uiCreate.vulnerableUntil,
        mitigatedSince: s.uiCreate.mitigatedSince,
      });
      await submitForm(form, 'Save node statuses');
      await gotoAdvisory(userPage, 'show', { id: advisoryId });
      await expect(content(userPage)).toContainText(s.publishedAffected.vpsHostname);
      await expect(content(page)).toContainText(expectedAdvisoryTime(originalPublishedAt));
      await expect(content(page)).toContainText('No updates posted.');
    } finally {
      await userContext.close();
    }
  });

  test('adds and removes published node membership only when explicitly selected', async ({ page }) => {
    const s = requireSecurityAdvisoryFixtures();
    const advisory = s.publishedNotAffected;
    const prefix = `node_${advisory.missingNodeId}`;
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    let form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_status_id"]`)).toHaveValue('');
    await expect(form.locator(`[name="${prefix}_add"]`)).not.toBeChecked();
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_status_id"]`)).toHaveValue('');
    await expect(form).toHaveAttribute('name', 'security_advisory_nodes');
    const formBounds = await form.boundingBox();
    const contentBounds = await content(page).boundingBox();
    expect(formBounds).not.toBeNull();
    expect(contentBounds).not.toBeNull();
    expect(formBounds.x + formBounds.width).toBeLessThanOrEqual(contentBounds.x + contentBounds.width + 1);
    await form.locator(`[name="${prefix}_add"]`).check();
    await setNodeStatus(form, advisory.missingNodeId, { state: 'not_affected' });
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_status_id"]`)).not.toHaveValue('');
    const existingId = await form.locator(`[name="${prefix}_status_id"]`).inputValue();
    await form.locator(`[name="${prefix}_status_id"]`).evaluate((field) => field.remove());
    await form.locator(`[name="${prefix}_state"]`).evaluate((field) => field.remove());
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_status_id"]`)).toHaveValue(existingId);
    await form.locator(`[name="${prefix}_remove"]`).check();
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_status_id"]`)).toHaveValue('');
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    await expect(formByAction(page, `action=nodes&id=${advisory.id}`)
      .locator(`[name="${prefix}_status_id"]`)).toHaveValue('');
  });

  test('removes a retired node assessment without requiring editable fields', async ({ page }) => {
    const advisory = requireSecurityAdvisoryFixtures().publishedNotAffected;
    const prefix = `node_${advisory.retiredNodeId}`;
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    const form = formByAction(page, `action=nodes&id=${advisory.id}`);
    await expect(form.locator(`[name="${prefix}_state"]`)).toHaveCount(0);
    await form.locator(`[name="${prefix}_remove"]`).check();
    await submitForm(form, 'Save node statuses');
    await gotoAdvisory(page, 'nodes', { id: advisory.id });
    await expect(formByAction(page, `action=nodes&id=${advisory.id}`)
      .locator(`[name="${prefix}_status_id"]`)).toHaveCount(0);
  });

  test('edits and clears published time and CVEs without resetting state', async ({ page }) => {
    const ui = requireSecurityAdvisoryFixtures().uiCreate;
    const correctedTime = `${ui.editedPublishedAt}:51`;
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    let form = formByAction(page, `action=edit&id=${advisoryId}`);
    await fillAdvisoryTextFields(form, { publishedAt: correctedTime, cves: ['CVE-2099-20004'] });
    await submitForm(form, 'Save');
    await expect(content(page)).toContainText(expectedAdvisoryTime(correctedTime));
    await expect(content(page)).toContainText('CVE-2099-20004');
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form.locator('[name="published_at"]')).toHaveValue(correctedTime);
    await fillAdvisoryTextFields(form, { publishedAt: '', cves: [] });
    await submitForm(form, 'Save');
    await expect(content(page)).toContainText('published');
    await expect(rowWithText(page, 'Published at:')).toContainText('-');
    await expect(content(page)).not.toContainText('CVE-2099-20004');
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form.locator('[name="published_at"]')).toHaveValue('');
    await expect(form.locator('[name="cves"]')).toHaveValue('');
    await fillAdvisoryTextFields(form, { publishedAt: originalPublishedAt, cves: ui.editedCves });
    await submitForm(form, 'Save');
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
      publishedAt: originalPublishedAt,
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

  test('confirms silent retraction and permanent advisory deletion', async ({ page }) => {
    await gotoAdvisory(page, 'show', { id: advisoryId });
    let form = formByAction(page, `action=retract&id=${advisoryId}`);
    await expect(form).toHaveAttribute('method', 'post');
    await expect(form.locator('[name="csrf_token"]')).not.toHaveValue('');
    await expect(form.locator('[name="expected_state"]')).toHaveValue('published');
    await expect(form.locator('[name="send_mail"]')).toHaveCount(0);
    await submitConfirmProtectedForm(page, form);
    await expect(content(page)).toContainText('retracted');
    await expect(content(page)).toContainText(expectedAdvisoryTime(originalPublishedAt));
    await expect(formByAction(page, `action=retract&id=${advisoryId}`)).toHaveCount(0);
    await gotoAdvisory(page, 'edit', { id: advisoryId });
    form = formByAction(page, `action=edit&id=${advisoryId}`);
    await expect(form.locator('[name="expected_state"]')).toHaveValue('retracted');
    await form.locator('[name="name"]').fill('Retracted advisory correction');
    await submitForm(form, 'Save');
    await expect(content(page)).toContainText('Retracted advisory correction');
    form = formByAction(page, `action=delete&id=${advisoryId}`);
    await expect(form).toHaveAttribute('method', 'post');
    await expect(form.locator('[name="csrf_token"]')).not.toHaveValue('');
    await expect(form.locator('[name="expected_state"]')).toHaveValue('retracted');
    await expect(form.locator('[name="send_mail"]')).toHaveCount(0);
    await submitConfirmProtectedForm(page, form);
    await expect(page).toHaveURL(/action=list/);
    await expect(content(page)).not.toContainText('Retracted advisory correction');
  });

});
