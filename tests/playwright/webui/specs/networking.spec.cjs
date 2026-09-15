const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout, loginButton, submitCredentials } = require('../lib/pages/auth.cjs');
const {
  formByAction,
  submitForm,
  runVpsadminctl,
  waitForVpsTransactionsSettled,
} = require('../lib/pages/webui.cjs');
const {
  expectNetworkingNotification,
  expectRouteAssignForm,
  rowWithText,
} = require('../lib/pages/networking.cjs');

const fixtures = readFixtures();
const networking = fixtures.networking;

function requireNetworkingFixtures() {
  if (!networking || !networking.ipAddresses || !networking.hostAddresses || !networking.vps) {
    throw new Error('networking coverage requires fixtures.networking');
  }

  return networking;
}

async function expectIpList(page, params, expectedAddr, options = {}) {
  const query = new URLSearchParams({
    page: 'networking',
    action: 'ip_addresses',
    list: '1',
    limit: '20',
    network: String(params.networkId),
    v: '4',
  });

  if (params.vps !== undefined) {
    query.set('vps', String(params.vps));
  }

  await page.goto(`/?${query.toString()}`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Routable IP Addresses');
  const filterForm = page.locator('form[name="ip-filter"]').first();
  await expect(filterForm).toBeVisible();
  if (expectedAddr) {
    await expect(rowWithText(page, expectedAddr)).toBeVisible();
  }

  if (options.admin) {
    await expect(filterForm.locator('input[name="user"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('User');
  } else {
    await expect(filterForm.locator('input[name="user"]')).toHaveCount(0);
    await expect(page.locator('#content-in')).toContainText('Owned');
  }
}

async function expectHostIpList(page, params, expectedAddr, options = {}) {
  const query = new URLSearchParams({
    page: 'networking',
    action: 'host_ip_addresses',
    list: '1',
    limit: '20',
    network: String(params.networkId),
    assigned: params.assigned || 'a',
    v: '4',
  });

  if (params.vps !== undefined) {
    query.set('vps', String(params.vps));
  }

  await page.goto(`/?${query.toString()}`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText('Host IP Addresses');
  const filterForm = page.locator('form[name="ip-filter"]').first();
  await expect(filterForm).toBeVisible();
  if (expectedAddr) {
    await expect(rowWithText(page, expectedAddr)).toBeVisible();
  }

  if (options.admin) {
    await expect(filterForm.locator('input[name="user"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText('User');
  } else {
    await expect(filterForm.locator('input[name="user"]')).toHaveCount(0);
    await expect(page.locator('#content-in')).toContainText('Owned');
  }
}

async function expectHostAddressActionForm(page, action, hostAddress) {
  await page.goto(`/?page=networking&action=${action}&id=${hostAddress.id}`, {
    waitUntil: 'domcontentloaded',
  });

  const form = formByAction(page, `action=${action}2&id=${hostAddress.id}`);
  await expect(form).toBeVisible();

  return form;
}

test.describe('networking browser coverage', () => {
  test('user networking lists, filters, and forms are wired', async ({ page }) => {
    const n = requireNetworkingFixtures();

    await login(page, fixtures.user);

    await expectIpList(page, { networkId: n.network.id });
    await expectHostIpList(
      page,
      {
        networkId: n.network.id,
        assigned: 'y',
        vps: n.vps.user_host_unassign.id,
      },
    );

    await page.goto(`/?page=networking&action=route_edit&id=${n.ipAddresses.user_route_unassign.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText(n.ipAddresses.user_route_unassign.addr);
    await expect(page.locator('#content-in')).toContainText('Host addresses');
    await expect(formByAction(page, 'action=route_edit_user')).toHaveCount(0);

    let form = await expectRouteAssignForm(page, n.ipAddresses.user_route_assign, n.vps.user_route_assign);
    await expect(form.locator('input[type="submit"][value="Add only route"]')).toBeVisible();
    await expect(form.locator('input[type="submit"][value*="Add route and an address"]')).toBeVisible();

    await page.goto(`/?page=networking&action=route_unassign&id=${n.ipAddresses.user_route_unassign.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Remove route from VPS');
    form = formByAction(page, `action=route_unassign2&id=${n.ipAddresses.user_route_unassign.id}`);
    await expect(form.locator('input[name="confirm"]')).toBeVisible();

    form = await expectHostAddressActionForm(page, 'hostaddr_assign', n.hostAddresses.user_host_assign);
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_unassign&id=${n.hostAddresses.user_host_unassign.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Remove host IP from a VPS');
    form = formByAction(page, `action=hostaddr_unassign2&id=${n.hostAddresses.user_host_unassign.id}`);
    await expect(form.locator('input[name="confirm"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_ptr&id=${n.hostAddresses.user_ptr.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=hostaddr_ptr2&id=${n.hostAddresses.user_ptr.id}`);
    await expect(form).toBeVisible();
    await form.locator('input[name="reverse_record_value"]').fill('ptr-user.webui-fixture.example.test');
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_new&ip=${n.multihost.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=hostaddr_new2&ip=${n.multihost.user.id}`);
    await expect(form).toBeVisible();
    await form.locator('textarea[name="host_addresses"]').fill(n.multihost.user.newHostAddress);
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(
      `/?page=networking&action=assignments&list=1&ip_addr=${n.ipAddresses.user_route_unassign.addr}&ip_prefix=${n.ipAddresses.user_route_unassign.prefix}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('IP address assignments');
    await expect(rowWithText(page, n.ipAddresses.user_route_unassign.addr)).toBeVisible();

    await page.goto(
      `/?page=networking&action=list&list=1&vps=${n.accounting.vpsId}&year=${n.accounting.year}&month=${n.accounting.month}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Monthly traffic');
    await expect(page.locator('#content-in')).toContainText('Statistics');
    await expect(rowWithText(page, n.accounting.networkInterfaceName)).toBeVisible();

    await page.goto(`/?page=networking&action=live&vps=${n.accounting.vpsId}&limit=10`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Live monitor');
    await expect(page.locator('#content-in input[name="vps"]')).toBeVisible();
    await expect(page.locator('table#live_monitor')).toContainText(n.accounting.networkInterfaceName);

    await logout(page, fixtures.user.username);
  });

  test('admin networking filters, admin columns, and admin-only forms are wired', async ({ page }) => {
    const n = requireNetworkingFixtures();

    await login(page, fixtures.admin);

    await expectIpList(page, { networkId: n.network.id }, undefined, {
      admin: true,
    });
    await expectHostIpList(
      page,
      {
        networkId: n.network.id,
        assigned: 'y',
        vps: n.vps.admin_host_unassign.id,
      },
      undefined,
      { admin: true },
    );

    await page.goto(`/?page=networking&action=route_edit&id=${n.ipAddresses.admin_owner_edit.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Ownership');
    let form = formByAction(page, `action=route_edit_user&id=${n.ipAddresses.admin_owner_edit.id}`);
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="user"]')).toBeVisible();
    await expect(form.locator('select[name="environment"]')).toBeVisible();
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    form = await expectRouteAssignForm(page, n.ipAddresses.admin_route_only, n.vps.admin_route_only);
    await expect(form.locator('input[type="submit"][value="Add only route"]')).toBeVisible();

    form = await expectRouteAssignForm(page, n.ipAddresses.admin_route_host, n.vps.admin_route_host);
    await expect(form.locator('input[type="submit"][value*="Add route and an address"]')).toBeVisible();

    await page.goto(`/?page=networking&action=route_unassign&id=${n.ipAddresses.admin_route_unassign.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Disown');
    form = formByAction(page, `action=route_unassign2&id=${n.ipAddresses.admin_route_unassign.id}`);
    await expect(form.locator('input[name="disown"]')).toBeVisible();
    await expect(form.locator('input[name="confirm"]')).toBeVisible();

    form = await expectHostAddressActionForm(page, 'hostaddr_assign', n.hostAddresses.admin_host_assign);
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_unassign&id=${n.hostAddresses.admin_host_unassign.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=hostaddr_unassign2&id=${n.hostAddresses.admin_host_unassign.id}`);
    await expect(form.locator('input[name="confirm"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_ptr&id=${n.hostAddresses.admin_ptr.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=hostaddr_ptr2&id=${n.hostAddresses.admin_ptr.id}`);
    await expect(form).toBeVisible();
    await form.locator('input[name="reverse_record_value"]').fill('ptr-admin.webui-fixture.example.test');
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(`/?page=networking&action=hostaddr_new&ip=${n.multihost.admin.id}`, {
      waitUntil: 'domcontentloaded',
    });
    form = formByAction(page, `action=hostaddr_new2&ip=${n.multihost.admin.id}`);
    await expect(form).toBeVisible();
    await form.locator('textarea[name="host_addresses"]').fill(n.multihost.admin.newHostAddress);
    await expect(form.locator('input[type="submit"]')).toBeVisible();

    await page.goto(
      `/?page=networking&action=assignments&list=1&user=${fixtures.user.id}&ip_addr=${n.ipAddresses.admin_route_unassign.addr}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('form[name="ip-filter"]').first().locator('input[name="user"]')).toBeVisible();
    await expect(page.locator('#content-in')).toContainText(fixtures.user.username);

    await page.goto(
      `/?page=networking&action=list&list=1&user=${fixtures.user.id}&year=${n.accounting.year}&month=${n.accounting.month}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Monthly traffic');
    await expect(page.locator('#content-in')).toContainText(fixtures.user.username);

    await page.goto(
      `/?page=networking&action=user_top&list=1&year=${n.accounting.year}&month=${n.accounting.month}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page.locator('#content-in')).toContainText('Top users');
    await expect(page.locator('#content-in')).toContainText(fixtures.user.username);

    await page.goto(`/?page=networking&action=live&user=${fixtures.user.id}&limit=10`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#content-in')).toContainText('Live monitor');
    await expect(page.locator('#content-in input[name="user"]')).toBeVisible();
    await expect(page.locator('form[action*="page=adminm"][action*="approval_requests"]').first()).toBeVisible();
    await expect(page.locator('table#live_monitor')).toContainText(n.accounting.networkInterfaceName);

    await logout(page, fixtures.admin.username);
  });
});


function showApiResource(name, id) {
  const response = runVpsadminctl([name, 'show', String(id)]);
  return (response.response || response)[name];
}

async function campaignAction(page, label) {
  await page.locator('#aside').getByRole('link', { name: label, exact: true }).click();
  await page.getByRole('button', { name: label, exact: true }).click();
  await expect(page.locator('#content')).not.toContainText('Action failed');
}

test('IP release campaign: navigation, bulk exemptions, notices and manual release', async ({ page }) => {
  const n = requireNetworkingFixtures();
  const ips = [n.ipAddresses.release_reason, n.ipAddresses.release_assigned, n.ipAddresses.release_exempt];
  const otherIp = n.ipAddresses.release_other_owner;
  await login(page, fixtures.admin);
  await page.goto('/?page=cluster');
  await page.locator('#aside').getByRole('link', { name: 'IP release campaigns', exact: true }).click();
  await expect(page.getByRole('columnheader', { name: 'Campaign', exact: true })).toBeVisible();
  await expect(page.locator('#content-in')).toContainText('No IP release campaigns.');
  await page.locator('#aside').getByRole('link', { name: 'Create campaign', exact: true }).click();
  const filters = page.locator('form[name="ip-release-filter"]');
  for (const name of ['ip_release_versions[]', 'ip_release_networks[]', 'ip_release_locations[]']) {
    await expect(filters.locator(`select[name="${name}"]`)).toHaveAttribute('multiple', '');
  }
  await expect(filters.locator('tr[id="ip_release_versions[]"]')).toHaveCSS('float', 'none');
  await filters.getByRole('button', { name: 'Preview addresses', exact: true }).click();
  const create = page.locator('form[name="ip-release-create"]');
  await expect(create).toHaveCount(1);
  await expect(create.getByRole('columnheader', { name: 'IP address', exact: true })).toBeVisible();
  await expect(create.locator('input[name="allow_keep"]')).toBeChecked();
  await create.getByRole('checkbox', { name: 'Select all', exact: true }).uncheck();
  for (const ip of [...ips, otherIp]) {
    await create.locator(`input[name="addresses[]"][value="${ip.id}"]`).check();
  }
  await expect(create.locator('input[name="label"]')).toHaveCount(0);
  const deadline = await create.locator('input[name="deadline"]').inputValue();
  await create.locator('input[name="deadline"]').fill('invalid date');
  await create.getByRole('button', { name: 'Create campaign', exact: true }).click();
  await expect(page.locator('#content')).toContainText('Enter the deadline as YYYY-MM-DD HH:MM.');
  await expect(create.locator('input[name="deadline"]')).toHaveValue('invalid date');
  for (const ip of [...ips, otherIp]) {
    await expect(create.locator(`input[name="addresses[]"][value="${ip.id}"]`)).toBeChecked();
  }
  await expect(create.getByRole('checkbox', { name: 'Select all', exact: true })).toHaveJSProperty('indeterminate', true);
  await create.locator('input[name="deadline"]').fill(deadline);
  const incomplete = await page.request.post('/?page=ip_release&action=create', {
    form: {
      csrf_token: await create.locator('input[name="csrf_token"]').inputValue(),
      deadline, 'addresses[]': String(ips[0].id),
    },
  });
  expect(await incomplete.text()).toContain('The address selection was incomplete.');
  await create.getByRole('button', { name: 'Create campaign', exact: true }).click();
  const campaignUrl = page.url();
  const campaignId = new URL(campaignUrl).searchParams.get('id');
  await page.locator('#aside').getByRole('link', { name: 'IP release campaigns', exact: true }).click();
  await page.getByRole('link', { name: `IP release campaign #${campaignId}`, exact: true }).click();
  await expect(page).toHaveURL(campaignUrl);
  await expect(page.locator('form[name="ip-release-edit"]')).toHaveCount(0);
  const bulk = page.locator('form[name="ip-release-exempt"]');
  await expect(bulk).toHaveCount(1);
  await expect(bulk.locator('form')).toHaveCount(0);
  await expect(bulk.getByRole('columnheader', { name: 'Original owner', exact: true })).toBeVisible();
  for (const ip of [...ips, otherIp]) {
    await expect(rowWithText(bulk, ip.addr)).toBeVisible();
  }
  await bulk.getByRole('checkbox', { name: 'Select all', exact: true }).check();
  await bulk.locator('textarea[name="reason"]').fill(' ');
  await bulk.getByRole('button', { name: 'Set exemption', exact: true }).click();
  await expect(page.locator('#content')).toContainText('Action failed');
  await expect(bulk.getByRole('checkbox', { name: 'Select all', exact: true })).toBeChecked();
  await bulk.locator('textarea[name="reason"]').fill('Batch reservation <script>window.unexpected = true</script>');
  await bulk.getByRole('button', { name: 'Set exemption', exact: true }).click();
  for (const ip of [...ips, otherIp]) {
    await expect(rowWithText(bulk, ip.addr)).toContainText('Exempted by an admin');
    await expect(rowWithText(bulk, ip.addr)).toContainText(fixtures.admin.username);
  }
  expect(await page.evaluate(() => window.unexpected)).toBeUndefined();
  await bulk.getByRole('checkbox', { name: 'Select all', exact: true }).check();
  await bulk.getByRole('button', { name: 'Remove exemption', exact: true }).click();
  for (const ip of [...ips, otherIp]) {
    await expect(rowWithText(bulk, ip.addr)).toContainText('Eligible for release');
  }
  await expect(page.locator('#aside').getByRole('link', { name: 'Send reminders', exact: true })).toHaveCount(0);
  await campaignAction(page, 'Send initial notices');
  await expect(page.locator('#aside').getByRole('link', { name: 'Send initial notices', exact: true })).toHaveCount(0);
  await expect(page.locator('#aside').getByRole('link', { name: 'Send reminders', exact: true })).toBeVisible();
  const response = runVpsadminctl(['ip_release_request', 'list']);
  const requests = (response.response || response).ip_release_requests;
  const requestId = requests.find(request => request.ip_release_campaign.id === Number(campaignId) && request.user.id === fixtures.user.id).id;
  const requestUrl = `/?page=ip_release&action=request&id=${requestId}`;
  const initialRequest = showApiResource('ip_release_request', requestId);
  const initialMail = showApiResource('mail_log', initialRequest.mail_log.id);
  expect(initialMail.text_html).toContain('Open in vpsAdmin');
  for (const ip of [ips[2], otherIp]) {
    await rowWithText(bulk, ip.addr).locator('input[name="addresses[]"]').check();
  }
  await bulk.locator('textarea[name="reason"]').fill('Approved reservation');
  await bulk.getByRole('button', { name: 'Set exemption', exact: true }).click();
  await logout(page, fixtures.admin.username);

  await login(page, fixtures.users.secondary);
  await page.goto('/?page=ip_release&action=list');
  await page.getByRole('link', { name: 'IP release request', exact: true }).click();
  await expect(rowWithText(page, otherIp.addr)).toContainText('Approved reservation');
  await expect(page.locator('#content-in')).not.toContainText(ips[0].addr);
  await expect(page.locator('#content-in')).not.toContainText(fixtures.admin.username);
  await logout(page, fixtures.users.secondary.username);

  // Follow the actual email button through the login redirect.
  await page.setContent(initialMail.text_html);
  await page.getByRole('link', { name: 'Open in vpsAdmin', exact: true }).click();
  await expect(page.locator('#content')).toContainText('Sign in to view your IP release request.');
  await loginButton(page).click({ noWaitAfter: true });
  await submitCredentials(page, fixtures.user.username, fixtures.user.password);
  await expect(page).toHaveURL(new RegExp(`page=ip_release.*id=${requestId}`));
  await page.locator('#aside').getByRole('link', { name: 'IP release requests', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Create campaign', exact: true })).toHaveCount(0);
  await page.getByRole('link', { name: 'IP release request', exact: true }).click();
  await expect(page.locator('#content-in')).not.toContainText(otherIp.addr);
  await expect(page.locator('#content-in')).not.toContainText(fixtures.admin.username);
  await expect(page.getByRole('columnheader', { name: 'Last release result', exact: true })).toHaveCount(0);
  await expect(page.locator('#content-in')).not.toContainText('Campaign settings');
  const keep = page.locator('form[name="ip-release-keep"]');
  await expect(keep.getByRole('columnheader', { name: 'User reason', exact: true })).toBeVisible();
  await rowWithText(keep, ips[0].addr).locator('input[name="addresses[]"]').check();
  await keep.locator('textarea[name="reason"]').fill('Migration <script>window.unexpected = true</script>');
  await submitForm(keep, 'Keep selected IPs');
  await expect(rowWithText(page, ips[0].addr)).toContainText('Kept with a reason');
  expect(await page.evaluate(() => window.unexpected)).toBeUndefined();
  const assign = await expectRouteAssignForm(page, ips[1], n.vps.ip_release);
  await submitForm(assign, 'Add only route');
  await expectNetworkingNotification(page, 'IP assigned');
  await waitForVpsTransactionsSettled(page, n.vps.ip_release.id);
  await page.goto(requestUrl);
  await expect(rowWithText(page, ips[1].addr)).toContainText('Assigned to an interface');
  await logout(page, fixtures.user.username);

  await login(page, fixtures.admin);
  await page.goto(campaignUrl);
  await expect(rowWithText(page, ips[0].addr)).toContainText(fixtures.user.username);
  await page.locator('#aside').getByRole('link', { name: 'Edit campaign', exact: true }).click();
  const edit = page.locator('form[name="ip-release-edit"]');
  await edit.locator('input[name="allow_keep"]').uncheck();
  await submitForm(edit, 'Save changes');
  await campaignAction(page, 'Send reminders');
  const remindedRequest = showApiResource('ip_release_request', requestId);
  const reminder = showApiResource('mail_log', remindedRequest.mail_log.id);
  expect(reminder.text_plain).toContain(ips[0].addr);
  expect(reminder.text_plain).not.toContain(ips[1].addr);
  expect(reminder.text_plain).not.toContain(ips[2].addr);
  await page.locator('#aside').getByRole('link', { name: 'Release eligible addresses', exact: true }).click();
  await expect(page.locator('#content-in')).toContainText('The planned release date has not arrived.');
  await page.getByRole('button', { name: 'Release eligible addresses', exact: true }).click();
  await expect(rowWithText(page, ips[0].addr)).toContainText('Released');
  await expect(rowWithText(page, ips[1].addr)).toContainText('Assigned to an interface');
  await expect(rowWithText(page, ips[2].addr)).toContainText('Exempted by an admin');
  await expect(page.locator('#aside').getByRole('link', { name: 'Release eligible addresses', exact: true })).toHaveCount(0);
  await page.locator('#aside').getByRole('link', { name: 'Notice history', exact: true }).click();
  await expect(page.getByRole('columnheader', { name: 'Recipient', exact: true })).toBeVisible();
  await expect(page.locator('#content-in')).toContainText('Initial notice');
  await expect(page.locator('#content-in')).toContainText('Reminder');
  await page.locator('#aside').getByRole('link', { name: 'Close without releasing IPs', exact: true }).click();
  await expect(page.locator('#content-in')).toContainText('Closing does not cancel a release already in progress');
  await page.getByRole('button', { name: 'Close without releasing IPs', exact: true }).click();
  await expect(page.locator('#aside').getByRole('link', { name: 'Edit campaign', exact: true })).toHaveCount(0);
  await expect(page.locator('input[name="addresses[]"]')).toHaveCount(0);
  expect(showApiResource('ip_address', otherIp.id).user.id).toBe(fixtures.users.secondary.id);
  await logout(page, fixtures.admin.username);
  await login(page, fixtures.user);
  await page.goto(requestUrl);
  await expect(page.locator('form[name="ip-release-keep"]')).toHaveCount(0);
  await page.locator('#aside').getByRole('link', { name: 'Notice history', exact: true }).click();
  await expect(page.locator('#content-in')).toContainText('Initial notice');
  await expect(page.locator('#content-in')).toContainText('Reminder');
  await expect(page.getByRole('columnheader', { name: 'Queued by', exact: true })).toHaveCount(0);
  await logout(page, fixtures.user.username);
});
