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

test('IP release campaign: notices, user retention, assignment and forced manual release', async ({ page }) => {
  const n = requireNetworkingFixtures();
  const ips = [n.ipAddresses.release_reason, n.ipAddresses.release_assigned, n.ipAddresses.release_exempt];
  await login(page, fixtures.admin);
  await page.goto(`/?page=ip_release&action=new&preview=1&version=4&user=${fixtures.user.id}`);
  const create = page.locator('form[name="ip-release-create"]');
  await expect(create.locator('input[name="allow_keep"]')).toBeChecked();
  await create.locator('input[name="label"]').fill('Browser IP release campaign');
  const incomplete = await page.request.post('/?page=ip_release&action=create', {
    form: {
      csrf_token: await create.locator('input[name="csrf_token"]').inputValue(),
      label: 'Incomplete selection',
      deadline: await create.locator('input[name="deadline"]').inputValue(),
      'addresses[]': String(ips[0].id),
    },
  });
  expect(await incomplete.text()).toContain('The address selection was incomplete.');
  for (const checkbox of await create.locator('input[name="addresses[]"]').all()) {
    await checkbox.uncheck();
  }
  for (const ip of ips) {
    await create.locator(`input[name="addresses[]"][value="${ip.id}"]`).check();
  }
  await submitForm(create, 'Create campaign');
  const campaignUrl = page.url();
  await expect(page.locator('#content')).toContainText('The planned release date has not arrived.');
  for (const ip of ips) {
    await expect(rowWithText(page, ip.addr)).toBeVisible();
  }
  await page.getByRole('button', { name: 'Send initial notices', exact: true }).click();
  await expect(page.locator('#content')).not.toContainText('Action failed');
  const exemption = rowWithText(page, ips[2].addr).locator('form');
  const requestId = new URL(await exemption.getAttribute('action'), campaignUrl).searchParams.get('id');
  const requestUrl = `/?page=ip_release&action=request&id=${requestId}`;
  const initialRequest = showApiResource('ip_release_request', requestId);
  const initialMail = showApiResource('mail_log', initialRequest.mail_log.id);
  expect(initialMail.text_html).toContain('Open in vpsAdmin');
  await exemption.locator('textarea[name="reason"]').fill('Approved reservation');
  await exemption.getByRole('button', { name: 'Set exemption', exact: true }).click();
  await expect(rowWithText(page, ips[2].addr)).toContainText('Exempted by an admin');
  await logout(page, fixtures.admin.username);

  // Follow the actual HTML email button through the login redirect.
  await page.setContent(initialMail.text_html);
  await page.getByRole('link', { name: 'Open in vpsAdmin', exact: true }).click();
  await expect(page.locator('#content')).toContainText('Sign in to view your IP release request.');
  await loginButton(page).click({ noWaitAfter: true });
  await submitCredentials(page, fixtures.user.username, fixtures.user.password);
  await expect(page).toHaveURL(new RegExp(`page=ip_release.*id=${requestId}`));
  await expect(rowWithText(page, ips[0].addr)).toContainText('Eligible for release');
  const keep = page.locator('form[name="ip-release-keep"]');
  await rowWithText(keep, ips[0].addr).locator('input[type="checkbox"]').check();
  await keep.locator('textarea[name="reason"]').fill('Migration <script>window.unexpected = true</script>');
  await submitForm(keep, 'Keep selected IPs');
  await expect(rowWithText(page, ips[0].addr)).toContainText('Kept with a reason');
  expect(await page.evaluate(() => window.unexpected)).toBeUndefined();
  await expect(rowWithText(page, ips[1].addr).getByRole('link', { name: 'Assign to a VPS' })).toBeVisible();
  const assign = await expectRouteAssignForm(page, ips[1], n.vps.ip_release);
  await submitForm(assign, 'Add only route');
  await expectNetworkingNotification(page, 'IP assigned');
  await waitForVpsTransactionsSettled(page, n.vps.ip_release.id);
  await page.goto(requestUrl);
  await expect(rowWithText(page, ips[1].addr)).toContainText('Assigned to an interface');
  await logout(page, fixtures.user.username);

  await login(page, fixtures.admin);
  await page.goto(campaignUrl);
  const edit = page.locator('form[name="ip-release-edit"]');
  await edit.locator('input[name="allow_keep"]').uncheck();
  await submitForm(edit, 'Save changes');
  await page.getByRole('button', { name: 'Send reminders', exact: true }).click();
  const remindedRequest = showApiResource('ip_release_request', requestId);
  const reminder = showApiResource('mail_log', remindedRequest.mail_log.id);
  expect(reminder.text_plain).toContain(ips[0].addr);
  expect(reminder.text_plain).not.toContain(ips[1].addr);
  expect(reminder.text_plain).not.toContain(ips[2].addr);
  await page.getByRole('button', { name: 'Release eligible addresses', exact: true }).click();
  await expect(rowWithText(page, ips[0].addr)).toContainText('Released');
  await expect(rowWithText(page, ips[1].addr)).toContainText('Assigned to an interface');
  await expect(rowWithText(page, ips[2].addr)).toContainText('Exempted by an admin');
  // Repeating the action keeps the released record and the two protections.
  await page.getByRole('button', { name: 'Release eligible addresses', exact: true }).click();
  await expect(rowWithText(page, ips[0].addr)).toContainText('Released');
  await logout(page, fixtures.admin.username);
  await login(page, fixtures.user);
  await page.goto(requestUrl);
  await expect(page.locator('form[name="ip-release-keep"]')).toHaveCount(0);
  await expect(page.locator('#content')).toContainText('user reasons do not prevent release');
  await page.getByRole('link', { name: 'Browser IP release campaign: Notice history', exact: true }).click();
  await expect(page.locator('#content-in')).toContainText('Initial notice');
  await expect(page.locator('#content-in')).toContainText('Reminder');
  await logout(page, fixtures.user.username);
});
