const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  createOomRule,
  deleteOomRule,
  editOomRule,
  rowWithText,
  selectIfPresent,
  setCheckboxIfPresent,
  submitMonitoringAction,
} = require('../lib/pages/support.cjs');

const fixtures = readFixtures();
const support = fixtures.support;

function requireSupportFixtures() {
  if (
    !support
    || !support.vps
    || !support.incidentReport
    || !support.oomReport
    || !support.outages
    || !support.monitoring
  ) {
    throw new Error('support page coverage requires fixtures.support');
  }

  return support;
}

function content(page) {
  return page.locator('#content-in');
}

function heading(page) {
  return page.locator('#content-in h1').first();
}

function formByName(page, name) {
  return page.locator(`form[name="${name}"]`).first();
}

async function fillEnglishText(form, summary, description = null) {
  const summaryInput = form.locator('input[name="en_summary"]');
  if ((await summaryInput.count()) > 0) {
    await summaryInput.fill(summary);
  }

  const descriptionInput = form.locator('textarea[name="en_description"]');
  if (description && (await descriptionInput.count()) > 0) {
    await descriptionInput.fill(description);
  }
}

test.describe('support and status browser coverage', () => {
  test('user incident list, filters, and detail are visible', async ({ page }) => {
    const s = requireSupportFixtures();

    await login(page, fixtures.user);
    await page.goto(
      `/?page=incidents&action=list&list=1&vps=${s.vps.id}&codename=${s.incidentReport.codename}`,
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Incident reports');
    const filter = formByName(page, 'incident-list');
    await expect(filter).toBeVisible();
    await expect(filter.locator('input[name="user"]')).toHaveCount(0);
    await expect(filter.locator('[name="mailbox"]')).toHaveCount(0);
    await expect(rowWithText(page, s.incidentReport.subject)).toContainText(
      s.incidentReport.codename,
    );
    await expect(content(page)).toContainText(s.incidentReport.ipAddress);

    await page.goto(`/?page=incidents&action=show&id=${s.incidentReport.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Incident report #${s.incidentReport.id}`);
    await expect(content(page)).toContainText(s.incidentReport.subject);
    await expect(content(page)).toContainText(s.incidentReport.text);
    await expect(content(page)).toContainText(s.incidentReport.codename);
    await expect(content(page)).not.toContainText(s.mailbox.label);

    await page.goto(`/?page=adminvps&action=info&veid=${s.vps.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page).locator('a[href*="page=incidents&action=new"]')).toHaveCount(0);

    await logout(page, fixtures.user.username);
  });

  test('admin incident filters, fields, and new report form are visible', async ({ page }) => {
    const s = requireSupportFixtures();

    await login(page, fixtures.admin);
    await page.goto(
      [
        '/?page=incidents&action=list&list=1',
        `user=${fixtures.user.id}`,
        `vps=${s.vps.id}`,
        `mailbox=${s.mailbox.id}`,
        `codename=${s.incidentReport.codename}`,
      ].join('&'),
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Incident reports');
    const filter = formByName(page, 'incident-list');
    await expect(filter.locator('input[name="user"]')).toBeVisible();
    await expect(filter.locator('input[name="vps"]')).toBeVisible();
    await expect(filter.locator('[name="mailbox"]')).toBeVisible();
    await expect(rowWithText(page, s.incidentReport.subject)).toContainText(
      fixtures.user.username,
    );

    await page.goto(`/?page=incidents&action=show&id=${s.incidentReport.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Incident report #${s.incidentReport.id}`);
    await expect(content(page)).toContainText(fixtures.user.username);
    await expect(content(page)).toContainText(s.mailbox.label);
    await expect(content(page)).toContainText(s.incidentReport.text);

    await page.goto(`/?page=incidents&action=new&vps=${s.vps.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('New incident report');
    const form = formByAction(page, `action=new&vps=${s.vps.id}`);
    await expect(form).toBeVisible();
    await expect(form.locator('select[name="ip_address_assignment"]')).toBeVisible();
    await form.locator('input[name="subject"]').fill('Webui browser incident form');
    await form.locator('textarea[name="text"]').fill('Form wiring only.');
    await form.locator('input[name="codename"]').fill('WEBUI-FORM');
    await expect(form.locator('[name="vps_action"]')).toBeVisible();
    await expect(form.locator('input[type="submit"]')).toHaveValue(/^\s*Report\s*$/);

    await logout(page, fixtures.admin.username);
  });

  test('user OOM reports and rule CRUD are wired', async ({ page }) => {
    const s = requireSupportFixtures();

    await login(page, fixtures.user);
    await page.goto(
      `/?page=oom_reports&action=list&list=1&vps=${s.vps.id}&oom_report_rule=${s.oomReport.ruleId}`,
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Out-of-memory Reports');
    const filter = formByName(page, 'user-session-filter');
    await expect(filter).toBeVisible();
    await expect(filter.locator('input[name="user"]')).toHaveCount(0);
    await expect(rowWithText(page, s.oomReport.killedName)).toContainText(s.vps.hostname);

    await page.goto(`/?page=oom_reports&action=show&id=${s.oomReport.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Out-of-memory Report for VPS ${s.vps.id}`);
    await expect(content(page)).toContainText(s.oomReport.cgroup);
    await expect(content(page)).toContainText(s.oomReport.killedName);

    await page.goto(`/?page=oom_reports&action=rule_list&vps=${s.vps.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText(`OOM report rules for VPS ${s.vps.id}`);
    await expect(rowWithText(page, s.oomReport.cgroup)).toBeVisible();
    await expect(formByAction(page, `action=rule_new&vps=${s.vps.id}`)).toBeVisible();

    const ruleId = await createOomRule(
      page,
      s.vps.id,
      'ignore',
      '/webui-playwright-user-rule',
    );
    await editOomRule(
      page,
      s.vps.id,
      ruleId,
      'notify',
      '/webui-playwright-user-rule-edited',
    );
    await deleteOomRule(page, s.vps.id, ruleId, '/webui-playwright-user-rule-edited');

    await logout(page, fixtures.user.username);
  });

  test('admin OOM filters, fields, and rule CRUD are wired', async ({ page }) => {
    const s = requireSupportFixtures();

    await login(page, fixtures.admin);
    await page.goto(
      [
        '/?page=oom_reports&action=list&list=1',
        `user=${fixtures.user.id}`,
        `vps=${s.vps.id}`,
        `oom_report_rule=${s.oomReport.ruleId}`,
      ].join('&'),
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Out-of-memory Reports');
    const filter = formByName(page, 'user-session-filter');
    await expect(filter.locator('input[name="user"]')).toBeVisible();
    await expect(filter.locator('input[name="vps"]')).toBeVisible();
    await expect(rowWithText(page, s.oomReport.killedName)).toContainText(
      fixtures.user.username,
    );

    await page.goto(`/?page=oom_reports&action=show&id=${s.oomReport.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText(fixtures.user.username);
    await expect(content(page)).toContainText(s.oomReport.killedName);

    const ruleId = await createOomRule(
      page,
      s.vps.id,
      'ignore',
      '/webui-playwright-admin-rule',
    );
    await editOomRule(
      page,
      s.vps.id,
      ruleId,
      'notify',
      '/webui-playwright-admin-rule-edited',
    );
    await deleteOomRule(page, s.vps.id, ruleId, '/webui-playwright-admin-rule-edited');

    await logout(page, fixtures.admin.username);
  });

  test('public and user outage lists, detail, and affected tabs are visible', async ({ page }) => {
    const s = requireSupportFixtures();
    const outage = s.outages.public;

    await page.goto(
      '/?page=outage&action=list&type=planned_outage&state=announced&impact=network',
      { waitUntil: 'domcontentloaded' },
    );
    await expect(heading(page)).toContainText('Outage list');
    await expect(formByName(page, 'outage-list')).toBeVisible();
    await expect(rowWithText(page, outage.summary)).toBeVisible();

    await page.goto(`/?page=outage&action=show&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Outage #${outage.id}`);
    await expect(content(page)).toContainText(outage.summary);
    await expect(content(page)).toContainText('Information');

    await login(page, fixtures.user);
    await page.goto(
      `/?page=outage&action=list&affected=yes&vps=${outage.vpsId}&state=announced`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(formByName(page, 'outage-list').locator('select[name="affected"]')).toBeVisible();
    await expect(rowWithText(page, outage.summary)).toBeVisible();

    await page.goto(`/?page=outage&action=show&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText('Status');
    await expect(content(page)).toContainText('Affected VPS');
    await expect(content(page)).toContainText(outage.vpsHostname);
    await expect(content(page)).toContainText('Affected exports');
    await expect(content(page)).toContainText(outage.exportPath);

    await page.goto(`/?page=outage&action=vps&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText('Affected VPS');
    await expect(rowWithText(page, outage.vpsHostname)).toBeVisible();

    await page.goto(`/?page=outage&action=exports&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText('Affected exports');
    await expect(rowWithText(page, outage.exportPath)).toBeVisible();

    await logout(page, fixtures.user.username);
  });

  test('admin outage filters, forms, updates, and state changes are wired', async ({ page }) => {
    const s = requireSupportFixtures();
    const outage = s.outages.admin;
    const staged = s.outages.staged;

    await login(page, fixtures.admin);
    await page.goto(
      [
        '/?page=outage&action=list&type=unplanned_outage&state=announced&impact=performance',
        `user=${fixtures.user.id}`,
        `vps=${s.outages.public.vpsId}`,
        `entity_name=Node`,
        `entity_id=${fixtures.node.id}`,
      ].join('&'),
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Outage list');
    const listFilter = formByName(page, 'outage-list');
    await expect(listFilter.locator('input[name="user"]')).toBeVisible();
    await expect(listFilter.locator('input[name="handled_by"]')).toBeVisible();
    await expect(listFilter.locator('input[name="entity_name"]')).toBeVisible();
    await expect(rowWithText(page, outage.summary)).toBeVisible();
    await expect(content(page)).toContainText('Users');
    await expect(content(page)).toContainText('VPS');

    await page.goto(`/?page=outage&action=show&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Outage #${outage.id}`);
    await expect(content(page)).toContainText('Auto-resolve');
    await expect(
      content(page).locator(`a[href*="action=users&id=${outage.id}"]`).first(),
    ).toBeVisible();
    await expect(
      content(page).locator(`a[href*="action=vps&id=${outage.id}"]`).first(),
    ).toBeVisible();
    await expect(
      content(page).locator(`a[href*="action=exports&id=${outage.id}"]`).first(),
    ).toBeVisible();

    await page.goto(`/?page=outage&action=users&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(content(page)).toContainText('Affected users');
    await expect(rowWithText(page, fixtures.user.username)).toBeVisible();

    await page.goto(`/?page=outage&action=vps&id=${outage.id}&user=${fixtures.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const vpsFilter = formByName(page, 'outage-list');
    await expect(vpsFilter.locator('input[name="action"]')).toHaveValue('vps');
    await expect(vpsFilter.locator('input[name="user"]')).toBeVisible();
    await expect(rowWithText(page, s.vps.hostname)).toBeVisible();

    await page.goto(`/?page=outage&action=exports&id=${outage.id}&user=${fixtures.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const exportFilter = formByName(page, 'outage-list');
    await expect(exportFilter.locator('input[name="action"]')).toHaveValue('exports');
    await expect(exportFilter.locator('input[name="user"]')).toBeVisible();
    await expect(rowWithText(page, s.outages.public.exportPath)).toBeVisible();

    await page.goto(`/?page=outage&action=report`, { waitUntil: 'domcontentloaded' });
    await expect(content(page)).toContainText('Outage Report');
    const reportForm = formByAction(page, 'action=report');
    await expect(reportForm).toBeVisible();
    await expect(reportForm.locator('select[name="nodes[]"]')).toBeVisible();
    await fillEnglishText(reportForm, 'Webui Support Report Form', 'Form wiring only.');

    await page.goto(`/?page=outage&action=edit_attrs&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Outage #${outage.id}`);
    const attrsForm = formByAction(page, `action=edit_attrs&id=${outage.id}`);
    await expect(attrsForm).toBeVisible();
    await attrsForm.locator('input[name="duration"]').fill('35');
    await fillEnglishText(attrsForm, 'Webui Support Admin Outage Edited');
    await submitForm(attrsForm, 'Save');
    await expect(heading(page)).toContainText(`Outage #${outage.id}`);
    await expect(content(page)).toContainText('Webui Support Admin Outage Edited');

    await page.goto(`/?page=outage&action=edit_systems&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const systemsForm = formByAction(page, `action=edit_systems&id=${outage.id}`);
    await expect(systemsForm).toBeVisible();
    await expect(systemsForm.locator('select[name="nodes[]"]')).toBeVisible();
    await expect(systemsForm.locator('select[name="handlers[]"]')).toBeVisible();
    await submitForm(systemsForm, 'Save');
    await expect(heading(page)).toContainText(`Outage #${outage.id}`);

    await page.goto(`/?page=outage&action=update&id=${outage.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const updateForm = formByAction(page, `action=update&id=${outage.id}`);
    await expect(updateForm).toBeVisible();
    await fillEnglishText(
      updateForm,
      'Webui Support Admin Update',
      'Deterministic browser update.',
    );
    await setCheckboxIfPresent(updateForm, 'send_mail', false);
    await submitForm(updateForm, 'Post update');
    await expectNotification(page, 'Update posted');
    await expect(content(page)).toContainText('Webui Support Admin Update');

    await page.goto(`/?page=outage&action=show&id=${staged.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const stateForm = formByAction(page, `action=set_state&id=${staged.id}`);
    await expect(stateForm).toBeVisible();
    await selectIfPresent(stateForm, 'state', 'announced');
    await setCheckboxIfPresent(stateForm, 'send_mail', false);
    await submitForm(stateForm, 'Change');
    await expectNotification(page, 'State set');
    await expect(content(page)).toContainText('announced');

    await logout(page, fixtures.admin.username);
  });

  test('user monitoring filters, detail, acknowledge, and ignore are wired', async ({ page }) => {
    const s = requireSupportFixtures();
    const showEvent = s.monitoring.user_show;

    await login(page, fixtures.user);
    await page.goto(
      [
        '/?page=monitoring&action=list',
        `monitor=${showEvent.monitor}`,
        `object_name=${showEvent.objectName}`,
        `object_id=${showEvent.objectId}`,
        'state=confirmed',
      ].join('&'),
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Monitored event list');
    const filter = formByName(page, 'monitoring-list');
    await expect(filter).toBeVisible();
    await expect(filter.locator('input[name="user"]')).toHaveCount(0);
    await expect(rowWithText(page, showEvent.label)).toContainText('confirmed');

    await page.goto(`/?page=monitoring&action=show&id=${showEvent.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Event #${showEvent.id}`);
    await expect(content(page)).toContainText(showEvent.issue);
    await expect(content(page)).toContainText('Acknowledge event');
    await expect(content(page)).toContainText('Ignore event');
    await expect(content(page)).toContainText('webui support show event');

    await submitMonitoringAction(
      page,
      'ack',
      s.monitoring.user_ack.id,
      'Event acknowledged',
    );
    await submitMonitoringAction(
      page,
      'ignore',
      s.monitoring.user_ignore.id,
      'Event ignored',
    );

    await logout(page, fixtures.user.username);
  });

  test('admin monitoring filters, fields, acknowledge, and ignore are wired', async ({ page }) => {
    const s = requireSupportFixtures();
    const event = s.monitoring.admin_ack;

    await login(page, fixtures.admin);
    await page.goto(
      [
        '/?page=monitoring&action=list',
        `user=${fixtures.user.id}`,
        `monitor=${event.monitor}`,
        `object_name=${event.objectName}`,
        `object_id=${event.objectId}`,
        'state=confirmed',
      ].join('&'),
      { waitUntil: 'domcontentloaded' },
    );

    await expect(heading(page)).toContainText('Monitored event list');
    const filter = formByName(page, 'monitoring-list');
    await expect(filter.locator('input[name="user"]')).toBeVisible();
    await expect(rowWithText(page, event.label)).toContainText(fixtures.user.username);

    await page.goto(`/?page=monitoring&action=show&id=${event.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText(`Event #${event.id}`);
    await expect(content(page)).toContainText(fixtures.user.username);
    await expect(content(page)).toContainText(event.issue);

    await submitMonitoringAction(page, 'ack', event.id, 'Event acknowledged');
    await submitMonitoringAction(
      page,
      'ignore',
      s.monitoring.admin_ignore.id,
      'Event ignored',
    );

    await logout(page, fixtures.admin.username);
  });
});
