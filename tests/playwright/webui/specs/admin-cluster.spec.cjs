const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  actionLink,
  content,
  fillIfPresent,
  gotoCluster,
  heading,
  linkParam,
  rowWithText,
  selectIfPresent,
  setCheckbox,
} = require('../lib/pages/cluster.cjs');

const fixtures = readFixtures();
const clusterAdmin = fixtures.clusterAdmin;

function requireClusterAdminFixtures() {
  if (
    !clusterAdmin
    || !clusterAdmin.environment
    || !clusterAdmin.locations
    || !clusterAdmin.networks
    || !clusterAdmin.dnsResolver
    || !clusterAdmin.resourcePackage
    || !clusterAdmin.osTemplate
    || !clusterAdmin.eventLog
    || !clusterAdmin.helpBox
  ) {
    throw new Error('admin cluster coverage requires fixtures.clusterAdmin');
  }

  return clusterAdmin;
}

function currentResourceId(page) {
  return new URL(page.url()).searchParams.get('id');
}

function resourcePackageItemRow(page, resourceLabel) {
  return page.locator('table.table-style01 tr', {
    has: page.locator('a[href*="resource_packages_item_edit"]'),
    hasText: resourceLabel,
  }).first();
}

async function submitLocationNetworkAdd(page, action, fixedParam, selectName, selectValue) {
  await gotoCluster(page, action, fixedParam);
  const form = formByAction(page, `action=${action}`);
  await expect(form).toBeVisible();
  await form.locator(`select[name="${selectName}"]`).selectOption(String(selectValue));
  await fillIfPresent(form, 'input[name="priority"]', '41');
  await setCheckbox(form, 'autopick', true);
  await setCheckbox(form, 'userpick', true);
  await submitForm(form, 'Add');
}

async function editLocationNetwork(page, rowText, priority) {
  const row = rowWithText(page, rowText);
  await expect(row).toBeVisible();
  await actionLink(row, 'location_network_edit').click();

  const form = formByAction(page, 'action=location_network_edit');
  await expect(form).toBeVisible();
  await fillIfPresent(form, 'input[name="priority"]', String(priority));
  await setCheckbox(form, 'autopick', true);
  await setCheckbox(form, 'userpick', false);
  await submitForm(form, 'Save');
  await expectNotification(page, 'Changes saved');
  await expect(form.locator('input[name="priority"]')).toHaveValue(String(priority));
}

async function fillTemplateForm(form, template, osFamilyId) {
  await selectIfPresent(form, 'os_family', osFamilyId);
  await fillIfPresent(form, 'input[name="label"]', template.label);
  await fillIfPresent(form, 'textarea[name="info"]', 'Webui cluster template coverage');
  await setCheckbox(form, 'enabled', true);
  await setCheckbox(form, 'supported', true);
  await fillIfPresent(form, 'input[name="order"]', '500');
  await selectIfPresent(form, 'hypervisor_type', 'vpsadminos');
  await selectIfPresent(form, 'cgroup_version', 'cgroup_any');
  await setCheckbox(form, 'manage_hostname', true);
  await setCheckbox(form, 'manage_dns_resolver', true);
  await setCheckbox(form, 'enable_script', true);
  await setCheckbox(form, 'enable_cloud_init', true);
  await fillIfPresent(form, 'input[name="vendor"]', template.vendor);
  await fillIfPresent(form, 'input[name="variant"]', template.variant);
  await fillIfPresent(form, 'input[name="arch"]', template.arch);
  await fillIfPresent(form, 'input[name="distribution"]', template.distribution);
  await fillIfPresent(form, 'input[name="version"]', template.version);
  await fillIfPresent(form, 'textarea[name="config"]', '{}');
}

test.describe.serial('admin cluster browser coverage', () => {
  test('overview, environment, location, node, VPS, network, and IP lists render', async ({ page }) => {
    const c = requireClusterAdminFixtures();

    await login(page, fixtures.admin);

    await gotoCluster(page);
    await expect(heading(page)).toContainText('Manage Cluster');
    await expect(content(page)).toContainText('Summary');
    await expect(content(page)).toContainText('Node list');
    await expect(content(page)).toContainText(fixtures.node.domainName);

    await gotoCluster(page, 'vps');
    await expect(content(page)).toContainText('Node list');
    await expect(content(page)).toContainText('Free');

    await gotoCluster(page, 'environments');
    await expect(content(page)).toContainText('Environments');
    await expect(rowWithText(page, c.environment.label)).toBeVisible();

    await gotoCluster(page, 'locations');
    await expect(content(page)).toContainText('Cluster locations list');
    await expect(rowWithText(page, c.locations.base.label)).toBeVisible();

    await gotoCluster(page, 'networks');
    await expect(content(page)).toContainText('Networks');
    await expect(rowWithText(page, c.networks.networkToLocation.label)).toBeVisible();

    await gotoCluster(page, 'ip_addresses');
    await expect(content(page)).toContainText('Routable IP Addresses');
    await expect(page.locator('form[name="ip-filter"]')).toBeVisible();

    await gotoCluster(page, 'host_ip_addresses');
    await expect(content(page)).toContainText('Host IP Addresses');
    await expect(page.locator('form[name="ip-filter"]')).toBeVisible();

    await logout(page, fixtures.admin.username);
  });

  test('system config view submits unchanged values', async ({ page }) => {
    requireClusterAdminFixtures();

    await login(page, fixtures.admin);
    await gotoCluster(page, 'sysconfig');
    await expect(content(page)).toContainText('System config');

    const form = formByAction(page, 'action=sysconfig_save');
    await expect(form).toBeVisible();
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'Changes saved');

    await logout(page, fixtures.admin.username);
  });

  test('DNS resolver create, edit, and delete work from cluster admin', async ({ page }) => {
    const c = requireClusterAdminFixtures();

    await login(page, fixtures.admin);

    await gotoCluster(page, 'dns');
    await expect(content(page)).toContainText('DNS Servers list');

    await gotoCluster(page, 'dns_new');
    let form = formByAction(page, 'action=dns_new_save');
    await expect(form).toBeVisible();
    await form.locator('input[name="dns_ip"]').fill(c.dnsResolver.ip);
    await form.locator('input[name="dns_label"]').fill(c.dnsResolver.label);
    await setCheckbox(form, 'dns_is_universal', true);
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'DNS server added');
    await expect(rowWithText(page, c.dnsResolver.label)).toBeVisible();

    let row = rowWithText(page, c.dnsResolver.label);
    await actionLink(row, 'dns_edit').click();
    form = formByAction(page, 'action=dns_edit_save');
    await expect(form).toBeVisible();
    await form.locator('input[name="dns_ip"]').fill(c.dnsResolver.updatedIp);
    await form.locator('input[name="dns_label"]').fill(c.dnsResolver.updatedLabel);
    await setCheckbox(form, 'dns_is_universal', true);
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'DNS server updated');
    await expect(rowWithText(page, c.dnsResolver.updatedLabel)).toBeVisible();

    row = rowWithText(page, c.dnsResolver.updatedLabel);
    await actionLink(row, 'dns_delete').click();
    form = formByAction(page, 'action=dns_delete');
    await expect(form).toBeVisible();
    await submitForm(form, 'Delete');
    await expectNotification(page, 'DNS server deleted');
    await expect(rowWithText(page, c.dnsResolver.updatedLabel)).toHaveCount(0);

    await logout(page, fixtures.admin.username);
  });

  test('environment edit and location create/edit forms save', async ({ page }) => {
    const c = requireClusterAdminFixtures();
    const created = c.locations.create;

    await login(page, fixtures.admin);

    await gotoCluster(page, 'env_edit', { id: c.environment.id });
    let form = formByAction(page, `action=env_save&id=${c.environment.id}`);
    await expect(form).toBeVisible();
    await fillIfPresent(form, 'textarea[name="description"]', c.environment.updatedDescription);
    await submitForm(form, 'Save');
    await expectNotification(page, 'Environment updated');
    await expect(rowWithText(page, c.environment.label)).toBeVisible();

    await gotoCluster(page, 'location_new');
    form = formByAction(page, 'action=location_new_save');
    await expect(form).toBeVisible();
    await form.locator('input[name="location_label"]').fill(created.label);
    await fillIfPresent(form, 'textarea[name="description"]', created.description);
    await form.locator('select[name="environment"]').selectOption(String(c.environment.id));
    await setCheckbox(form, 'has_ipv6', false);
    await form.locator('input[name="remote_console_server"]').fill(created.remoteConsoleServer);
    await form.locator('input[name="domain"]').fill(created.domain);
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'Location created');

    let row = rowWithText(page, created.label);
    await expect(row).toBeVisible();
    await actionLink(row, 'location_edit').click();
    form = formByAction(page, 'action=location_edit_save');
    await expect(form).toBeVisible();
    await form.locator('input[name="location_label"]').fill(created.editedLabel);
    await fillIfPresent(form, 'textarea[name="description"]', created.editedDescription);
    await setCheckbox(form, 'has_ipv6', false);
    await form.locator('input[name="remote_console_server"]').fill(created.remoteConsoleServer);
    await form.locator('input[name="domain"]').fill(created.editedDomain);
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'Changes saved');
    await expect(rowWithText(page, created.editedLabel)).toBeVisible();

    await logout(page, fixtures.admin.username);
  });

  test('resource package and item create, edit, and delete work', async ({ page }) => {
    const c = requireClusterAdminFixtures();
    const pkg = c.resourcePackage;

    await login(page, fixtures.admin);

    await gotoCluster(page, 'resource_packages');
    await expect(content(page)).toContainText('Cluster resource packages');

    await gotoCluster(page, 'resource_packages_new');
    let form = formByAction(page, 'action=resource_packages_new');
    await expect(form).toBeVisible();
    await form.locator('input[name="label"]').fill(pkg.label);
    await submitForm(form, 'Create');
    await expectNotification(page, 'Package created');
    const packageId = currentResourceId(page);

    form = formByAction(page, `action=resource_packages_edit&id=${packageId}`);
    await expect(form).toBeVisible();
    await form.locator('input[name="label"]').fill(pkg.updatedLabel);
    await submitForm(form, 'Update');
    await expectNotification(page, 'Package updated');
    form = formByAction(page, `action=resource_packages_edit&id=${packageId}`);
    await expect(form.locator('input[name="label"]')).toHaveValue(pkg.updatedLabel);

    form = formByAction(page, `action=resource_packages_item_add&id=${packageId}`);
    await expect(form).toBeVisible();
    await form.locator('select[name="cluster_resource"]').selectOption(String(pkg.resourceId));
    await form.locator('input[name="value"]').fill('2');
    await submitForm(form, 'Add');
    await expect(resourcePackageItemRow(page, pkg.resourceLabel)).toContainText('2');

    let row = resourcePackageItemRow(page, pkg.resourceLabel);
    const itemId = await linkParam(actionLink(row, 'resource_packages_item_edit'), 'item');
    await actionLink(row, 'resource_packages_item_edit').click();
    form = formByAction(page, 'action=resource_packages_item_edit');
    await expect(form).toBeVisible();
    await form.locator('input[name="value"]').fill('3');
    await submitForm(form, 'Save');
    await expect(resourcePackageItemRow(page, pkg.resourceLabel)).toContainText('3');

    await gotoCluster(page, 'resource_packages_item_delete', {
      id: packageId,
      item: itemId,
    });
    form = formByAction(page, 'action=resource_packages_item_delete');
    await expect(form).toBeVisible();
    await setCheckbox(form, 'confirm', true, { required: true });
    await submitForm(form, 'Remove');
    await expect(resourcePackageItemRow(page, pkg.resourceLabel)).toHaveCount(0);

    await gotoCluster(page, 'resource_packages_delete', { id: packageId });
    form = formByAction(page, 'action=resource_packages_delete');
    await expect(form).toBeVisible();
    await setCheckbox(form, 'confirm', true, { required: true });
    await submitForm(form, 'Remove');
    await expect(rowWithText(page, pkg.updatedLabel)).toHaveCount(0);

    await logout(page, fixtures.admin.username);
  });

  test('location-network and IP address admin flows work', async ({ page }) => {
    const c = requireClusterAdminFixtures();
    const netToLoc = c.networks.networkToLocation;
    const locToNet = c.networks.locationToNetwork;
    const ipNet = c.networks.ipAdd;
    const otherLocation = c.locations.other;

    await login(page, fixtures.admin);

    await gotoCluster(page, 'network_locations', { network: netToLoc.id });
    await expect(content(page)).toContainText('Network locations');
    await expect(rowWithText(page, c.locations.base.label)).toBeVisible();

    await submitLocationNetworkAdd(
      page,
      'location_network_add_loctonet',
      { network: netToLoc.id },
      'location',
      otherLocation.id,
    );
    await expectNotification(page, 'Location added to network');
    await editLocationNetwork(page, otherLocation.label, 42);
    await gotoCluster(page, 'network_locations', { network: netToLoc.id });
    await expect(content(page)).toContainText('Network locations');
    await expect(rowWithText(page, otherLocation.label)).toBeVisible();

    await gotoCluster(page, 'location_networks', { location: otherLocation.id });
    await expect(content(page)).toContainText('Location networks');

    await submitLocationNetworkAdd(
      page,
      'location_network_add_nettoloc',
      { location: otherLocation.id },
      'network',
      locToNet.id,
    );
    await expectNotification(page, 'Network added to location');
    await editLocationNetwork(page, locToNet.label, 43);
    await gotoCluster(page, 'location_networks', { location: otherLocation.id });
    await expect(content(page)).toContainText('Location networks');
    await expect(rowWithText(page, locToNet.label)).toBeVisible();

    await gotoCluster(page, 'ipaddr_add');
    let form = formByAction(page, 'action=ipaddr_add2');
    await expect(form).toBeVisible();
    await form.locator('textarea[name="ip_addresses"]').fill(ipNet.address);
    await form.locator('select[name="network"]').selectOption(String(ipNet.id));
    await submitForm(form, 'Add');
    await expectNotification(page, 'IP addresses added');

    await gotoCluster(page, 'ip_addresses', {
      list: 1,
      limit: 20,
      network: ipNet.id,
      v: 4,
    });
    await expect(content(page)).toContainText('Routable IP Addresses');
    await expect(rowWithText(page, ipNet.hostAddress)).toBeVisible();

    await gotoCluster(page, 'host_ip_addresses', {
      list: 1,
      limit: 20,
      network: ipNet.id,
      assigned: 'n',
      v: 4,
    });
    await expect(content(page)).toContainText('Host IP Addresses');
    await expect(rowWithText(page, ipNet.hostAddress)).toBeVisible();

    await logout(page, fixtures.admin.username);
  });

  test('OS template and node administration forms render', async ({ page }) => {
    const c = requireClusterAdminFixtures();
    const template = c.osTemplate;

    await login(page, fixtures.admin);

    await gotoCluster(page, 'templates');
    await expect(content(page)).toContainText('Templates list');
    await expect(rowWithText(page, fixtures.osTemplates.primary.label)).toBeVisible();

    await gotoCluster(page, 'templates_edit', { id: fixtures.osTemplates.primary.id });
    let form = formByAction(page, 'action=templates_edit');
    await expect(form).toBeVisible();
    await submitForm(form, 'Save changes');
    await expectNotification(page, 'Changes saved');

    await gotoCluster(page, 'template_register');
    form = formByAction(page, 'action=template_register');
    await expect(form).toBeVisible();
    await fillTemplateForm(form, template, template.osFamilyId);
    await expect(form.locator('input[name="label"]')).toHaveValue(template.label);
    await expect(form.locator('input[name="vendor"]')).toHaveValue(template.vendor);
    await expect(form.locator('input[name="arch"]')).toHaveValue(template.arch);

    await gotoCluster(page, 'newnode');
    await expect(content(page)).toContainText('Register new server into cluster');
    form = formByAction(page, 'action=newnode_save');
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="name"]')).toBeVisible();
    await expect(form.locator('input[name="ip_addr"]')).toBeVisible();

    await gotoCluster(page, 'node_edit', { node_id: fixtures.node.id });
    form = formByAction(page, `action=node_edit_save&node_id=${fixtures.node.id}`);
    await expect(form).toBeVisible();

    await logout(page, fixtures.admin.username);
  });

  test('maintenance lock, event log, and help box actions work', async ({ page }) => {
    const c = requireClusterAdminFixtures();
    const eventLog = c.eventLog;
    const helpBox = c.helpBox;

    await login(page, fixtures.admin);

    await gotoCluster(page, 'maintenance_lock', {
      type: 'cluster',
      obj_id: '',
      lock: 1,
    });
    let form = formByAction(page, 'action=set_maintenance_lock');
    await expect(form).toBeVisible();
    await form.locator('input[name="reason"]').fill('Webui cluster maintenance coverage');
    await submitForm(form, 'Lock');
    await expectNotification(page, 'Cluster: maintenance ON');

    await actionLink(page, 'set_maintenance_lock', {
      type: 'cluster',
      lock: 0,
    }).click();
    await expectNotification(page, 'Cluster: maintenance OFF');

    await gotoCluster(page, 'eventlog');
    form = formByAction(page, 'action=log_add');
    await expect(form).toBeVisible();
    await form.locator('textarea[name="en_message"]').fill(eventLog.message);
    await form.locator('textarea[name="cs_message"]').fill(eventLog.message);
    await submitForm(form, 'Add');
    await expectNotification(page, 'News message added');
    let row = rowWithText(page, eventLog.message);
    await expect(row).toBeVisible();

    await actionLink(row, 'log_edit').click();
    form = formByAction(page, 'action=log_edit_save');
    await expect(form).toBeVisible();
    await form.locator('textarea[name="en_message"]').fill(eventLog.updatedMessage);
    await form.locator('textarea[name="cs_message"]').fill(eventLog.updatedMessage);
    await submitForm(form, 'Update');
    await expectNotification(page, 'Log message updated');
    row = rowWithText(page, eventLog.updatedMessage);
    await expect(row).toBeVisible();

    await actionLink(row, 'log_del').click();
    await expectNotification(page, 'Log message deleted');
    await expect(rowWithText(page, eventLog.updatedMessage)).toHaveCount(0);

    await gotoCluster(page, 'helpboxes');
    form = formByAction(page, 'action=helpboxes_add');
    await expect(form).toBeVisible();
    await form.locator('input[name="page"]').fill(helpBox.page);
    await form.locator('input[name="action"]').fill(helpBox.action);
    await form.locator('textarea[name="content"]').fill(helpBox.content);
    await submitForm(form, 'Add');
    await expectNotification(page, 'Help box added');
    row = rowWithText(page, helpBox.content);
    await expect(row).toBeVisible();

    await actionLink(row, 'helpboxes_edit').click();
    form = formByAction(page, 'action=helpboxes_edit_save');
    await expect(form).toBeVisible();
    await form.locator('textarea[name="content"]').fill(helpBox.updatedContent);
    await submitForm(form, 'Update');
    await expectNotification(page, 'Help box updated');
    row = rowWithText(page, helpBox.updatedContent);
    await expect(row).toBeVisible();

    await actionLink(row, 'helpboxes_del').click();
    await expectNotification(page, 'Help box deleted');
    await expect(rowWithText(page, helpBox.updatedContent)).toHaveCount(0);

    await logout(page, fixtures.admin.username);
  });
});
