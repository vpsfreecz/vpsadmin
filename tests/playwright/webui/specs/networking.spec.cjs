const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  formByAction,
} = require('../lib/pages/webui.cjs');
const {
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
