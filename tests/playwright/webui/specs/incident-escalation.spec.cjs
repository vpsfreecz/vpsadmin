const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { gotoVpsDetail, submitForm } = require('../lib/pages/webui.cjs');
const { createAdminVps, vpsListRow } = require('../lib/pages/vps.cjs');

const fixtures = readFixtures();

test('Incident escalation summary, admin settings and member visibility', async ({ page }) => {
  await login(page, fixtures.admin);
  const vpsId = await createAdminVps(page, fixtures, `webui-incidents-${Date.now().toString(36)}`, {
    userId: fixtures.user.id,
    nodeId: fixtures.node.id,
    bootAfterCreate: false,
    resources: { diskspace: 1024 },
  });
  await gotoVpsDetail(page, vpsId);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.oom-details"]')).toBeVisible();
  await expect(page.locator('#content-in')).toContainText('No outstanding shutdown');
  await expect(page.locator('#content-in')).toContainText('no shutdown is scheduled');
  const settings = page.locator('form[name="incident-policy"]');
  await settings.locator('[name="incident_warning_limit_override"]').fill('6');
  await settings.locator('[name="incident_stop_limit_override"]').fill('12');
  await settings.locator('[name="incident_enforcement_enabled"]').selectOption('0');
  await submitForm(settings);
  await expect(settings.locator('[name="incident_warning_limit_override"]')).toHaveValue('6');
  await expect(settings.locator('[name="incident_stop_limit_override"]')).toHaveValue('12');
  await expect(settings.locator('[name="incident_enforcement_enabled"]')).toHaveValue('0');

  await page.goto(`/?page=adminvps&action=list&user=${fixtures.user.id}&incident_policy=oomd&incident_status=clear&incident_enforcement_enabled=0`);
  await expect(vpsListRow(page, vpsId)).toContainText('7 days: 0/6; 30 days: 0/12');
  await expect(vpsListRow(page, vpsId)).toContainText('Automatic shutdown exempt');
  await page.locator('form[name="vps-filter"] select[name="incident_status"]').selectOption('stop_threshold');
  await submitForm(page.locator('form[name="vps-filter"]'));
  await expect(vpsListRow(page, vpsId)).toHaveCount(0);
  // An empty result must retain filters so an admin can return to the overview.
  await expect(page.locator('select[name="incident_status"]')).toHaveValue('stop_threshold');
  await logout(page, fixtures.admin.username);

  await login(page, fixtures.user);
  await gotoVpsDetail(page, vpsId);
  await expect(page.locator('form[name="incident-policy"]')).toHaveCount(0);
  await expect(page.locator('form[name="incident-policy-reset"]')).toHaveCount(0);
  await expect(page.locator('#content-in')).toContainText('Exempt');
  await page.locator('#content-in a[href*="codename=oomd"]').click();
  await expect(page).toHaveURL(new RegExp(`page=incidents.*vps=${vpsId}.*codename=oomd`));

  await gotoVpsDetail(page, vpsId);
  const token = await page.locator('input[name="csrf_token"]').first().inputValue();
  const response = await page.request.post(`/?page=adminvps&action=incident_policy&veid=${vpsId}`, {
    form: { csrf_token: token, incident_policy: 'oomd', incident_warning_limit_override: '1', incident_stop_limit_override: '1', incident_enforcement_enabled: '1' },
  });
  expect(await response.text()).toContain('Access forbidden');

  await page.locator('#langbox a[href*="newlang=cs_CZ.utf8"]').click();
  await gotoVpsDetail(page, vpsId);
  await expect(page.locator('[data-vpsadmin-doc-id="vps.oom-details"]')).toContainText('Incidenty přetížení paměti VPS');
  // Restore English before using existing authentication helpers.
  await page.locator('#langbox a[href*="newlang=en_US.utf8"]').click();
  await logout(page, fixtures.user.username);

  await login(page, fixtures.admin);
  await gotoVpsDetail(page, vpsId);
  await expect(settings.locator('[name="incident_warning_limit_override"]')).toHaveValue('6');
  await expect(settings.locator('[name="incident_stop_limit_override"]')).toHaveValue('12');
  await submitForm(page.locator('form[name="incident-policy-reset"]'));
  await expect(settings.locator('[name="incident_warning_limit_override"]')).toHaveValue('');
  await expect(settings.locator('[name="incident_stop_limit_override"]')).toHaveValue('');
  // Resetting limits preserves the stop exemption.
  await expect(settings.locator('[name="incident_enforcement_enabled"]')).toHaveValue('0');
  await logout(page, fixtures.admin.username);
});
