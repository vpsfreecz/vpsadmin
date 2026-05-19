const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  actionLink,
  rowWithText,
  setCheckbox,
  toggleRecord,
} = require('../lib/pages/dns.cjs');

const fixtures = readFixtures();
const dns = fixtures.dns;

function requireDnsFixtures() {
  if (!dns || !dns.zones || !dns.records || !dns.createNames) {
    throw new Error('dns coverage requires fixtures.dns');
  }

  return dns;
}

async function submitZoneUpdate(page, zone, options = {}) {
  await page.goto(`/?page=dns&action=zone_show&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText(zone.name);

  const form = formByAction(page, `action=zone_update&id=${zone.id}`);
  await expect(form).toBeVisible();

  if (options.defaultTtl) {
    await form.locator('input[name="default_ttl"]').fill(String(options.defaultTtl));
  }

  if (options.email) {
    await form.locator('input[name="email"]').fill(options.email);
  }

  if (options.enabled !== undefined) {
    await setCheckbox(form, 'enabled', options.enabled);
  }

  await submitForm(form, 'Save');
  await expectNotification(page, 'DNS zone updated');
}

async function expectZoneUpdateForm(page, zone) {
  await page.goto(`/?page=dns&action=zone_show&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText(zone.name);

  const form = formByAction(page, `action=zone_update&id=${zone.id}`);
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="default_ttl"]')).toBeVisible();
  await expect(form.locator('input[name="enabled"]')).toBeVisible();

  return form;
}

async function expectZoneDeleteForm(page, zone) {
  await page.goto(`/?page=dns&action=zone_delete&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('Delete zone');

  const form = formByAction(page, `action=zone_delete2&id=${zone.id}`);
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="confirm"]')).toBeVisible();
}

async function submitRecordCreate(page, zone, name, content, options = {}) {
  await page.goto(`/?page=dns&action=zone_show&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('New record');

  const form = formByAction(page, `action=record_new&zone=${zone.id}`);
  await expect(form).toBeVisible();
  await form.locator('input[name="name"]').fill(name);
  await form.locator('select[name="type"]').selectOption(options.type || 'A');
  await form.locator('textarea[name="content"]').fill(content);

  if (options.ttl) {
    await form.locator('input[name="ttl"]').fill(String(options.ttl));
  }

  if (options.userId) {
    await form.locator('input[name="user"]').fill(String(options.userId));
  }

  await submitForm(form, 'Add record');
  await expectNotification(page, 'Record added');
}

async function expectRecordCreateForm(page, zone) {
  await page.goto(`/?page=dns&action=zone_show&id=${zone.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('New record');

  const form = formByAction(page, `action=record_new&zone=${zone.id}`);
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="name"]')).toBeVisible();
  await expect(form.locator('select[name="type"]')).toBeVisible();
  await expect(form.locator('textarea[name="content"]')).toBeVisible();

  return form;
}

async function submitRecordEdit(page, record, content, options = {}) {
  await page.goto(`/?page=dns&action=record_edit&id=${record.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('update record');

  const form = formByAction(page, `action=record_edit2&id=${record.id}`);
  await expect(form).toBeVisible();

  if (options.ttl) {
    await form.locator('input[name="ttl"]').fill(String(options.ttl));
  }

  await form.locator('textarea[name="content"]').fill(content);

  if (options.comment !== undefined) {
    await form.locator('textarea[name="comment"]').fill(options.comment);
  }

  if (options.userId) {
    await form.locator('input[name="user"]').fill(String(options.userId));
  }

  await submitForm(form, 'Update');
  await expectNotification(page, 'Record updated');
}

async function expectRecordEditForm(page, record) {
  await page.goto(`/?page=dns&action=record_edit&id=${record.id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in')).toContainText('update record');

  const form = formByAction(page, `action=record_edit2&id=${record.id}`);
  await expect(form).toBeVisible();
  await expect(form.locator('textarea[name="content"]')).toBeVisible();

  return form;
}

async function expectRecordDeleteLink(page, record) {
  await page.goto(`/?page=dns&action=zone_show&id=${record.zoneId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(actionLink(page, 'record_edit', { id: record.id })).toBeVisible();

  const link = actionLink(page, 'record_delete', { id: record.id });
  await expect(link).toBeVisible();

  const href = await link.getAttribute('href');
  expect(href).toContain('action=record_delete');
  expect(href).toContain(`id=${record.id}`);
  expect(href).toContain(`zone=${record.zoneId}`);
}

async function expectPrimaryZoneCreateForm(page, options = {}) {
  await page.goto('/?page=dns&action=primary_zone_new', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Create a new primary DNS zone');

  const form = formByAction(page, 'action=primary_zone_new2');
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="name"]')).toBeVisible();
  await expect(form.locator('input[name="email"]')).toBeVisible();

  if (options.admin) {
    await expect(form.locator('input[name="user"]')).toBeVisible();
  }
}

async function expectSecondaryZoneCreateForm(page, options = {}) {
  await page.goto('/?page=dns&action=secondary_zone_new', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Create a new secondary DNS zone');

  const form = formByAction(page, 'action=secondary_zone_new2');
  await expect(form).toBeVisible();
  await expect(form.locator('input[name="name"]')).toBeVisible();

  if (options.admin) {
    await expect(form.locator('input[name="user"]')).toBeVisible();
  }
}

async function setTsigAlgorithm(form, algorithm) {
  const select = form.locator('select[name="algorithm"]');

  if ((await select.count()) > 0) {
    await select.selectOption(algorithm);
    return;
  }

  await form.locator('input[name="algorithm"]').fill(algorithm);
}

test.describe('DNS browser coverage', () => {
  test('user DNS zones, records, logs, PTR, and resolver views are wired', async ({ page }) => {
    const d = requireDnsFixtures();

    await login(page, fixtures.user);

    await page.goto('/?page=dns&action=zone_list&list=1&limit=20', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('DNS zones');
    await expect(page.locator('form[name="user-session-filter"] input[name="user"]')).toHaveCount(0);
    await expect(rowWithText(page, d.zones.user_update.name)).toBeVisible();

    await page.goto('/?page=dns&action=primary_zone_list&list=1&limit=20', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Primary DNS zones');
    await expect(rowWithText(page, d.zones.user_update.name)).toBeVisible();

    await page.goto('/?page=dns&action=secondary_zone_list&list=1&limit=20', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Secondary DNS zones');
    await expect(page.locator('#content-in')).toContainText('Create new secondary zone');

    await expectZoneUpdateForm(page, d.zones.user_update);

    await page.goto(`/?page=dns&action=dnssec_records&id=${d.zones.user_dnssec.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('DNSSEC records');
    await expect(page.locator('#content-in')).toContainText(String(d.dnssec.userKeyId));
    await expect(page.locator('#content-in')).toContainText('DNSKEY record');

    await expectRecordCreateForm(page, d.zones.user_record_create);
    await expectRecordEditForm(page, d.records.user_edit);

    await toggleRecord(page, d.records.user_toggle, 'record_toggle_enable', false);
    await toggleRecord(page, d.records.user_ddns, 'record_toggle_ddns', true);
    await expectRecordDeleteLink(page, d.records.user_delete);

    await expectZoneDeleteForm(page, d.zones.user_delete);

    await expectPrimaryZoneCreateForm(page);
    await expectSecondaryZoneCreateForm(page);

    await page.goto(
      `/?page=dns&action=record_log&list=1&dns_zone=${d.logs.recordUser.zoneId}&name=${d.logs.recordUser.name}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('DNS record log');
    await expect(page.locator('#content-in')).toContainText(d.logs.recordUser.zoneName);

    await page.goto(
      `/?page=dns&action=transfer_log&dns_zone=${d.logs.transferUser.zoneId}&reason_code=${d.logs.transferUser.reasonCode}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('DNS transfer log');
    await expect(page.locator('#content-in')).toContainText(d.logs.transferUser.reasonCode);

    await page.goto(
      `/?page=dns&action=ptr_list&list=1&vps=${fixtures.networking.vps.user_ptr.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Reverse records');
    let ptrFilterForm = page.locator('form[name="ip-filter"]').first();
    await expect(ptrFilterForm).toBeVisible();
    await expect(ptrFilterForm.locator('input[name="vps"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('Host address');
    await expect(page.locator('#content-in')).toContainText('Reverse record');

    await page.goto('/?page=dns&action=resolver_list', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in')).toContainText('DNS resolvers');
    await expect(page.locator('#content-in')).toContainText('Test resolver');

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.user_update.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).not.toContainText('Add server');
    await expect(page.locator('#aside')).not.toContainText('Servers');

    await logout(page, fixtures.user.username);
  });

  test('admin DNS server, zone, record, transfer, TSIG, PTR, and log views are wired', async ({ page }) => {
    const d = requireDnsFixtures();

    await login(page, fixtures.admin);

    await page.goto('/?page=dns&action=server_list', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in')).toContainText('DNS servers');
    await expect(page.locator('#content-in')).toContainText(d.server.name);
    await expect(page.locator('#content-in')).toContainText('User zones');

    await page.goto(`/?page=dns&action=zone_list&list=1&limit=20&user=${fixtures.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('form[name="user-session-filter"] input[name="user"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('Role');
    await expect(page.locator('#content-in')).toContainText('Source');
    await expect(rowWithText(page, d.zones.admin_update.name)).toBeVisible();

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.admin_update.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('User');
    await expect(page.locator('#content-in')).toContainText('Source');
    await expect(page.locator('#content-in')).toContainText('Role');
    await expect(page.locator('#content-in')).toContainText('Add server');
    await expectZoneUpdateForm(page, d.zones.admin_update);

    await expectZoneDeleteForm(page, d.zones.admin_delete);

    await page.goto(`/?page=dns&action=server_zone_new&id=${d.zones.admin_server_zone_add.id}`, {
      waitUntil: 'domcontentloaded',
    });
    let form = formByAction(page, `action=server_zone_new2&id=${d.zones.admin_server_zone_add.id}`);
    await expect(form).toBeVisible();
    await expect(form.locator('select[name="dns_server"]')).toBeVisible();
    await expect(form.locator('select[name="type"]')).toBeVisible();

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.admin_server_zone_delete.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(actionLink(page, 'server_zone_delete', {
      server_zone: d.serverZones.delete.id,
    })).toBeVisible();

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.admin_transfer_add.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(actionLink(page, 'zone_transfer_new', {
      id: d.zones.admin_transfer_add.id,
    })).toBeVisible();

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.admin_transfer_delete.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(actionLink(page, 'zone_transfer_delete', {
      transfer: d.transfers.delete.id,
    })).toBeVisible();

    await expectPrimaryZoneCreateForm(page, { admin: true });
    await expectSecondaryZoneCreateForm(page, { admin: true });

    await page.goto(`/?page=dns&action=dnssec_records&id=${d.zones.admin_dnssec.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(String(d.dnssec.adminKeyId));
    await expect(page.locator('#content-in')).toContainText('DS record');

    await page.goto(`/?page=dns&action=zone_show&id=${d.zones.admin_record.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('User');
    form = await expectRecordCreateForm(page, d.zones.admin_record);
    await expect(form.locator('input[name="user"]')).toBeVisible();
    form = await expectRecordEditForm(page, d.records.admin_edit);
    await expect(form.locator('input[name="user"]')).toBeVisible();
    await toggleRecord(page, d.records.admin_toggle, 'record_toggle_enable', false);
    await toggleRecord(page, d.records.admin_ddns, 'record_toggle_ddns', true);
    await expectRecordDeleteLink(page, d.records.admin_delete);

    await page.goto(
      `/?page=dns&action=record_log&list=1&user=${fixtures.admin.id}&dns_zone_name=${encodeURIComponent(d.logs.recordAdmin.zoneName)}&name=${d.logs.recordAdmin.name}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('form[name="user-session-filter"] input[name="user"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText(d.logs.recordAdmin.zoneName);

    await page.goto(
      `/?page=dns&action=transfer_log&dns_zone=${d.logs.transferAdmin.zoneId}&dns_server_zone=${d.logs.transferAdmin.serverZoneId}&reason_code=${d.logs.transferAdmin.reasonCode}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('form[name="dns-transfer-log-filter"] input[name="dns_zone"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText(d.logs.transferAdmin.reasonCode);

    await page.goto(`/?page=dns&action=tsig_key_list&user=${fixtures.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('TSIG keys');
    await expect(page.locator('#content-in')).toContainText(d.tsigKeys.user_list.name);

    await page.goto('/?page=dns&action=tsig_key_new', { waitUntil: 'domcontentloaded' });
    form = formByAction(page, 'action=tsig_key_new2');
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="user"]')).toBeVisible();
    await expect(form.locator('input[name="name"]')).toBeVisible();
    await setTsigAlgorithm(form, 'hmac-sha256');

    await page.goto(`/?page=dns&action=tsig_key_delete&id=${d.tsigKeys.admin_delete.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=tsig_key_delete2&id=${d.tsigKeys.admin_delete.id}`);
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="confirm"]')).toBeVisible();

    await page.goto(
      `/?page=dns&action=ptr_list&list=1&user=${fixtures.user.id}&vps=${fixtures.networking.vps.admin_ptr.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    const ptrFilterForm = page.locator('form[name="ip-filter"]').first();
    await expect(ptrFilterForm).toBeVisible();
    await expect(ptrFilterForm.locator('input[name="user"]')).toBeVisible();
    await expect(ptrFilterForm.locator('input[name="vps"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('Host address');
    await expect(page.locator('#content-in')).toContainText('Reverse record');

    await page.goto('/?page=dns&action=resolver_list', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in')).toContainText('DNS resolvers');
    await expect(page.locator('#content-in')).toContainText('Test resolver');

    await logout(page, fixtures.admin.username);
  });
});
