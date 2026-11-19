const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { gotoVpsDetail, submitForm } = require('../lib/pages/webui.cjs');
const { createAdminVps, vpsListRow } = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();

const policyHeading = (page, key) => page.locator(`[id="incident-policy-${key}"]`).locator('..');
const followingTable = (heading) => heading.locator('xpath=following-sibling::table[1]');

async function expectPeriodRows(table, counts, limits, language = 'en', current = false) {
  await expect(table.locator('thead th')).toHaveText(language === 'cs'
    ? ['Období', 'Počet incidentů', 'Limit', 'Akce']
    : ['Period', 'Incidents', 'Limit', 'Action']);
  const rows = table.locator('tbody tr');
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0).locator('td')).toHaveText([
    language === 'cs' ? (current ? 'Za posledních 7 dní' : '7 dní') : (current ? 'Last 7 days' : '7 days'), String(counts[0]), String(limits[0]),
    language === 'cs' ? 'Upozornění' : 'Warning',
  ]);
  await expect(rows.nth(1).locator('td')).toHaveText([
    language === 'cs' ? (current ? 'Za posledních 30 dní' : '30 dní') : (current ? 'Last 30 days' : '30 days'), String(counts[1]), String(limits[1]),
    language === 'cs' ? 'Vypnutí VPS' : 'VPS stop',
  ]);
}

async function expectCurrentPolicies(page, count, language = 'en') {
  const limits = { fixture_alpha: [5, 10], fixture_beta: [3, 6] };
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incidents.policy"]')).toHaveCount(2);
  for (const [key, pair] of Object.entries(limits)) {
    const table = followingTable(policyHeading(page, key));
    await expectPeriodRows(table.locator('table'), [count, count], pair, language, true);
  }
}

async function gotoReport(page, id) {
  await page.goto(`/?page=incidents&action=show&id=${id}`);
  await expect(page.locator('#content-in h1')).toContainText(`Incident report #${id}`);
}

async function expectSavedPolicies(page, count) {
  const headings = page.locator('[data-vpsadmin-doc-id="incident-report.policy"]');
  await expect(headings).toHaveText(['First fixture policy', 'Second fixture policy']);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policies"]')).toHaveText('Matched policies');
  await expect(page.locator('#content-in')).toContainText('These counts and limits were saved when this report was evaluated.');
  for (const [index, limits] of [[0, [5, 10]], [1, [3, 6]]]) {
    await expectPeriodRows(followingTable(headings.nth(index)).locator('table'), [count, count], limits);
  }
}

// The fixture registry supplies policies; the browser never selects a source key.
test('VPS incident navigation, saved policies, scoped drafts and shared shutdown permission', async ({ page }) => {
  await login(page, fixtures.admin);
  const vpsId = await createAdminVps(page, fixtures, `webui-incidents-${Date.now().toString(36)}`, {
    userId: fixtures.user.id,
    nodeId: fixtures.node.id,
    bootAfterCreate: false,
    resources: { diskspace: 1024 },
  });
  await gotoVpsDetail(page, vpsId);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.oom-details"]')).toHaveCount(0);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incidents.warning"]')).toHaveCount(0);
  const detailUrl = page.url();
  const reports = page.locator('[data-vpsadmin-doc-id="vps.incident-reports.menu"]');
  await expect(reports).toHaveText('Incident reports');
  const reportsUrl = new URL(await reports.getAttribute('href'), detailUrl);
  expect(reportsUrl.searchParams.get('vps')).toBe(String(vpsId));
  expect(reportsUrl.searchParams.get('return')).toBe(new URL(detailUrl).pathname + new URL(detailUrl).search);
  await reports.click();
  await expect(page.locator('#content-in h1')).toHaveText('Incident reports');
  await expect(page.locator('form[name="incident-list"] [name="vps"]')).toHaveValue(String(vpsId));
  await page.locator('#aside').getByRole('link', { name: 'Back', exact: true }).click();
  await expect(page).toHaveURL(detailUrl);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]')).toHaveText('Incident policies');
  await page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]').click();
  await expect(page).toHaveURL(new RegExp(`action=incidents.*veid=${vpsId}`));
  await expect(page.locator('div[data-vpsadmin-doc-id="vps.incidents.page"]')).toHaveCount(1);
  await expect(page.locator('#content-in h2').filter({ hasText: /^Incident policies$/ })).toHaveCount(0);
  await expectCurrentPolicies(page, 0);
  const policies = page.locator('[data-vpsadmin-doc-id="vps.incidents.policy"]');
  const policyCount = await policies.count();
  expect(policyCount).toBe(2);
  const policyForms = page.locator('form[name^="incident-policy-"]');
  await expect(policyForms).toHaveCount(2);
  const settings = policyForms.first();
  const otherSettings = policyForms.nth(1);
  const otherWarning = await otherSettings.locator('[name="warning_limit_override"]').inputValue();
  const otherStop = await otherSettings.locator('[name="stop_limit_override"]').inputValue();
  const key = await settings.locator('[name="policy_key"]').inputValue();
  const permission = page.locator('form[name="incident-permission"]');
  await expect(permission).toHaveCount(1);
  await permission.locator('[name="incident_enforcement_enabled"]').selectOption('0');
  await submitForm(permission);
  // Blank raw overrides inherit; a number remains explicit even at the default.
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveAttribute('placeholder', '5');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveAttribute('placeholder', '10');
  await expect(settings.locator('select, button[type="button"]')).toHaveCount(0);
  await submitForm(settings);
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('');
  await settings.locator('[name="warning_limit_override"]').fill('5');
  await submitForm(settings);
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('5');
  await expect(settings.locator('[name="warning_limit_override"]')).not.toHaveAttribute('placeholder');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('');
  await settings.locator('[name="warning_limit_override"]').fill('6');
  await settings.locator('[name="stop_limit_override"]').fill('12');
  await submitForm(settings);
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('6');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('12');
  await expect(otherSettings.locator('[name="warning_limit_override"]')).toHaveValue(otherWarning);
  await expect(otherSettings.locator('[name="stop_limit_override"]')).toHaveValue(otherStop);
  await expect(permission.locator('[name="incident_enforcement_enabled"]')).toHaveValue('0');
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveAttribute('min', '1');

  // Clearing a custom draft cannot reveal the unknown inherited target.
  await settings.locator('[name="warning_limit_override"]').fill('');
  await expect(settings.locator('[name="warning_limit_override"]')).not.toHaveAttribute('placeholder');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('12');
  await page.reload();
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('6');
  await settings.locator('[name="warning_limit_override"]').fill('');
  await submitForm(settings);
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveAttribute('placeholder', '5');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('12');
  // Native validation and server rejection both preserve the other draft.
  await settings.locator('[name="stop_limit_override"]').fill('0');
  expect(await settings.locator('[name="stop_limit_override"]').evaluate((input) => input.checkValidity())).toBe(false);
  await settings.evaluate((form) => { form.noValidate = true; });
  await submitForm(settings);
  await expect(page.locator('#perex')).toContainText('Enter a positive whole number, or leave the limit empty.');
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('0');
  await otherSettings.locator('[name="warning_limit_override"]').fill('8');
  await settings.locator('[name="stop_limit_override"]').fill('');
  await expect(otherSettings.locator('[name="warning_limit_override"]')).toHaveValue('8');
  await submitForm(settings);
  await expect(settings.locator('[name="warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="stop_limit_override"]')).toHaveAttribute('placeholder', '10');
  await expect(otherSettings.locator('[name="warning_limit_override"]')).toHaveValue(otherWarning);
  await expect(otherSettings.locator('[name="stop_limit_override"]')).toHaveValue(otherStop);
  await expect(permission.locator('[name="incident_enforcement_enabled"]')).toHaveValue('0');
  await expect(page.locator('#content-in details')).toHaveCount(0);
  await expect(page.locator('#content-in a[href*="action=sysconfig"]')).toHaveCount(0);
  await expect(page.locator('#content-in')).not.toContainText('Each policy counts reports');
  await expect(settings.locator('[data-incident-unit]')).toHaveText(['reports in 7 days', 'reports in 30 days']);
  await settings.locator('[name="warning_limit_override"]').fill('1');
  await expect(settings.locator('[data-incident-unit]').first()).toHaveText('report in 7 days');
  await page.reload();

  await page.goto(`/?page=adminvps&action=list&user=${fixtures.user.id}&from_id=${vpsId - 1}`);
  await expect(vpsListRow(page, vpsId)).toBeVisible();
  await expect(vpsListRow(page, vpsId)).not.toContainText('7 days:');
  await expect(page.locator('[data-vpsadmin-doc-id="vps.oom-summary"]')).toHaveCount(0);
  await expect(page.locator('form [name="incident_enforcement_enabled"]')).toHaveCount(0);

  const saved = fixtures.incidentPolicies;
  expect(saved.vpsId).toBeGreaterThan(0);
  await gotoVpsDetail(page, saved.vpsId);
  await expect(page.locator('#perex')).toContainText('Too many incident reports: warning limit reached');
  await page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]').click();
  await expectCurrentPolicies(page, 3);
  await page.goto(`/?page=adminvps&action=list&user=${fixtures.user.id}&from_id=${saved.vpsId - 1}`);
  await expect(vpsListRow(page, saved.vpsId)).toBeVisible();
  await expect(vpsListRow(page, saved.vpsId).locator('[data-vpsadmin-doc-id="vps.incidents.warning"] img'))
    .toHaveAttribute('alt', 'Too many incident reports: warning limit reached');

  await gotoReport(page, saved.reports.matched);
  await expectSavedPolicies(page, 1);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy-diagnostics"]')).toHaveCount(0);
  await gotoReport(page, saved.reports.error);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy"]')).toHaveCount(0);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy-diagnostics"]')).toBeVisible();
  await expect(page.locator('#content-in')).toContainText('Error stage');
  await expect(page.locator('#content-in')).toContainText('Error class');
  await expect(page.locator('#content-in')).not.toContainText('Fixture selection error');
  await gotoReport(page, saved.reports.unmatched);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy"]')).toHaveCount(0);
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy-diagnostics"]')).toBeVisible();
  await expect(page.locator('#content-in')).toContainText('No matching policies');
  await logout(page, fixtures.admin.username);

  await login(page, fixtures.user);
  await gotoVpsDetail(page, vpsId);
  await page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]').click();
  await expect(page.locator('form[name^="incident-policy-"]')).toHaveCount(0);
  await expect(page.locator('form[name="incident-permission"]')).toHaveCount(0);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incidents.policy"]')).toHaveCount(policyCount);
  await expect(page.locator('#content-in')).toContainText('Exempt');
  const consoleUrl = await page.locator('a[href*="page=console"]').first().getAttribute('href');
  const csrfToken = new URL(consoleUrl, page.url()).searchParams.get('t');
  const response = await page.request.post(`/?page=adminvps&action=incident_policy&veid=${vpsId}`, {
    form: { csrf_token: csrfToken, policy_key: key, warning_limit_override: '1', stop_limit_override: '1' },
  });
  expect(await response.text()).toContain('Access forbidden');

  await expect(page.locator('#content-in details')).toHaveCount(0);
  await page.locator(`#content-in a[href*="policy_key=${encodeURIComponent(key)}"]`).first().click();
  await expect(page).toHaveURL(new RegExp(`page=incidents.*vps=${vpsId}.*policy_key=${encodeURIComponent(key)}`));

  await gotoReport(page, saved.reports.matched);
  await expectSavedPolicies(page, 1);
  const activeLink = followingTable(page.locator('[data-vpsadmin-doc-id="incident-report.policy"]').first())
    .getByRole('link', { name: 'Incident policies', exact: true });
  await expect(activeLink).toHaveAttribute('href', `?page=adminvps&action=incidents&veid=${saved.vpsId}#incident-policy-fixture_alpha`);
  await activeLink.click();
  await expect(policyHeading(page, 'fixture_alpha')).toBeVisible();
  await expectCurrentPolicies(page, 3);
  await gotoReport(page, saved.reports.auditOnly);
  await expectSavedPolicies(page, 2);
  for (const id of [saved.reports.unmatched, saved.reports.error]) {
    await gotoReport(page, id);
    await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policies"]')).toHaveText('Matched policies');
    await expect(page.locator('#content-in')).toContainText('Policy information is unavailable for this report.');
    await expect(page.locator('#content-in')).not.toContainText('No matching policies');
    await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy-diagnostics"]')).toHaveCount(0);
    await expect(page.locator('#content-in')).not.toContainText('Error stage');
    await expect(page.locator('#content-in')).not.toContainText('Fixture selection error');
  }
  await gotoReport(page, saved.reports.retired);
  const retired = page.locator('[data-vpsadmin-doc-id="incident-report.policy"]');
  await expect(retired).toHaveText('Retired fixture policy');
  const retiredTable = followingTable(retired);
  await expect(retiredTable.getByRole('link', { name: 'Incident policies', exact: true })).toHaveCount(0);
  await retiredTable.getByRole('link', { name: 'Incident history', exact: true }).click();
  await expect(page.locator('form[name="incident-list"] [name="policy_key"]')).toHaveValue(saved.retiredKey);
  const filter = page.locator('form[name="incident-list"] select[name="policy_key"]');
  await expect(filter.locator('option')).toHaveText(['All policies', 'First fixture policy', 'Second fixture policy', saved.retiredKey]);
  await page.locator('form[name="incident-list"] [name="from_id"]').fill('999999');
  await filter.selectOption('fixture_alpha');
  await expect(page.locator('form[name="incident-list"] [name="from_id"]')).toHaveValue('');
  await submitForm(page.locator('form[name="incident-list"]'));
  await expect(page).toHaveURL(new RegExp(`vps=${saved.vpsId}.*policy_key=fixture_alpha`));
  await expect(page.locator(`#content-in a[href="?page=incidents&action=show&id=${saved.reports.matched}"]`).first()).toBeVisible();
  await expect(page.locator(`#content-in a[href="?page=incidents&action=show&id=${saved.reports.retired}"]`)).toHaveCount(0);
  await page.goto(`/?page=incidents&action=list&list=1&vps=${saved.vpsId}&policy_key=${saved.retiredKey}`);
  await expect(page.locator(`#content-in a[href="?page=incidents&action=show&id=${saved.reports.retired}"]`).first()).toBeVisible();
  await expect(page.locator(`#content-in a[href="?page=incidents&action=show&id=${saved.reports.matched}"]`)).toHaveCount(0);
  await gotoReport(page, saved.reports.notice);
  await expect(page.locator('#content-in')).toContainText('First fixture policy');
  await expect(page.locator('#content-in')).not.toContainText('Second fixture policy');
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policies"]')).toHaveCount(0);
  await expect(page.locator('#content-in a[href*="#incident-policy-fixture_alpha"]')).toBeVisible();
  await page.goto(`/?page=incidents&action=show&id=${saved.reports.foreign}`);
  await expect(page.locator('#perex')).toBeVisible();
  await expect(page.locator('#content-in')).not.toContainText('Policy fixture foreign');
  await expect(page.locator('[data-vpsadmin-doc-id="incident-report.policy"]')).toHaveCount(0);

  await gotoVpsDetail(page, vpsId);
  await page.locator('#langbox a[href*="newlang=cs_CZ.utf8"]').click();
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incident-reports.menu"]')).toHaveText('Incidenty');
  await expect(page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]')).toHaveText('Pravidla incidentů');
  await page.locator('[data-vpsadmin-doc-id="vps.incidents.menu"]').click();
  await expect(page.locator('div[data-vpsadmin-doc-id="vps.incidents.page"]')).toHaveCount(1);
  await expect(page.locator('#content-in h2').filter({ hasText: /^Pravidla incidentů$/ })).toHaveCount(0);
  await expectCurrentPolicies(page, 0, 'cs');
  await expect(page.locator('#content-in')).not.toContainText('Každé pravidlo počítá hlášení');
  await expect(page.locator('#content-in details')).toHaveCount(0);
  await page.locator('#langbox a[href*="newlang=en_US.utf8"]').click();
  await logout(page, fixtures.user.username);
});
