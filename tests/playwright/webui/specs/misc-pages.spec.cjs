const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const { expectConsoleIframe } = require('../lib/pages/console.cjs');
const {
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');

const fixtures = readFixtures();
const managed = fixtures.adminMembers && fixtures.adminMembers.managed;
const storage = fixtures.storage;
const networking = fixtures.networking;
const supportVps = fixtures.vps && fixtures.vps.fixtures && fixtures.vps.fixtures.support;

function content(page) {
  return page.locator('#content-in');
}

function heading(page) {
  return page.locator('#content-in h1').first();
}

function rowWithText(page, text) {
  return page.locator('table.table-style01 tr', { hasText: text }).first();
}

function futureDate(days) {
  const date = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  const pad = (value) => String(value).padStart(2, '0');

  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join('-');
}

function futureDateTime(days) {
  return `${futureDate(days)} 00:00:00`;
}

async function linkParam(page, locator, name) {
  const href = await locator.getAttribute('href');

  if (!href) {
    throw new Error(`Link has no href while reading ${name}`);
  }

  return new URL(href, page.url()).searchParams.get(name);
}

async function checkRadio(form, name, value) {
  const radio = form.locator(`input[name="${name}"][value="${value}"]`);

  await radio.check({ force: true });
  await expect(radio).toBeChecked();
}

async function setUserDataFormat(form, format) {
  const select = form.locator('select[name="format"]');

  if ((await select.count()) > 0) {
    await select.selectOption(format);
    return;
  }

  await form.locator('input[name="format"]').fill(format);
}

async function fillUserDataForm(form, label, format, scriptBody) {
  await form.locator('input[name="label"]').fill(label);
  await setUserDataFormat(form, format);
  await form.locator('textarea[name="content"]').fill(scriptBody);
}

async function setReminder(page, resource, id, value, dateValue = null) {
  await page.goto(`/?page=reminder&resource=${resource}&id=${id}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(content(page)).toContainText('Set e-mail reminder');

  const form = formByAction(page, `page=reminder&action=set&resource=${resource}&id=${id}`);
  await expect(form).toBeVisible();
  await checkRadio(form, 'remind_in', value);

  if (value === 'date') {
    await form.locator('input[name="remind_after_date"]').fill(dateValue || futureDate(21));
  }

  await submitForm(form, 'Go >>');
  await expectNotification(page, 'Mail reminder set');
  await expect(page).toHaveURL(new RegExp(`page=reminder.*resource=${resource}.*id=${id}`));
}

function requireMiscFixtures() {
  if (!managed || !managed.userPayment) {
    throw new Error('misc-pages requires fixtures.adminMembers.managed.userPayment');
  }

  if (!storage || !storage.datasets || !storage.datasets.nas_list) {
    throw new Error('misc-pages requires fixtures.storage.datasets.nas_list');
  }

  if (!networking || !networking.hostAddresses || !networking.hostAddresses.user_ptr) {
    throw new Error('misc-pages requires fixtures.networking.hostAddresses.user_ptr');
  }

  if (!supportVps) {
    throw new Error('misc-pages requires fixtures.vps.fixtures.support');
  }
}

test.describe.serial('miscellaneous webui page coverage', () => {
  test('user reminders, lifetime access gating, and user data actions work', async ({ page }) => {
    requireMiscFixtures();

    await login(page, fixtures.user);

    for (const value of ['1w', '2w', 'date', 'never']) {
      await setReminder(
        page,
        'user',
        fixtures.user.id,
        value,
        value === 'date' ? futureDate(28) : null,
      );
    }

    await page.goto(
      `/?page=lifetimes&action=set_state&resource=user&id=${fixtures.user.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(formByAction(page, 'page=lifetimes&action=set_state')).toHaveCount(0);
    await expect(page.locator('[name="object_state"]')).toHaveCount(0);

    await page.goto(`/?page=adminm&action=edit&id=${fixtures.user.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(formByAction(page, 'page=lifetimes&action=set_state')).toHaveCount(0);

    const vpsId = supportVps.id;

    await page.goto('/?page=userdata&action=list', { waitUntil: 'domcontentloaded' });
    await expect(heading(page)).toContainText('User data');
    const userDataFilterForm = page.locator('form[name="user-session-filter"]').first();
    await expect(userDataFilterForm).toBeVisible();
    await expect(userDataFilterForm.locator('input[name="user"]')).toHaveCount(0);

    const label = `Webui Misc User Data ${Date.now().toString(36)}`;
    const editedLabel = `${label} Edited`;
    const script = "#!/bin/sh\nprintf 'webui misc user data\\n' > /root/webui-misc.txt\n";

    await page.goto('/?page=userdata&action=new', { waitUntil: 'domcontentloaded' });
    let form = formByAction(page, 'page=userdata&action=new');
    await expect(form).toBeVisible();
    await expect(form.locator('input[name="user"]')).toHaveCount(0);
    await fillUserDataForm(form, label, 'script', script);
    await submitForm(form, 'Add');
    await expectNotification(page, 'User data saved');
    await expect(rowWithText(page, label)).toBeVisible();

    const editLink = rowWithText(page, label).locator('a[href*="action=edit"]').first();
    const dataId = await linkParam(page, editLink, 'id');
    await editLink.click();
    await expect(content(page)).toContainText('Edit user data');

    form = formByAction(page, `page=userdata&action=edit&id=${dataId}`);
    await expect(form).toBeVisible();
    await fillUserDataForm(form, editedLabel, 'script', script);
    await submitForm(form, 'Save');
    await expectNotification(page, 'User data saved');
    await expect(rowWithText(page, editedLabel)).toBeVisible();

    await page.goto(`/?page=userdata&action=edit&id=${dataId}`, {
      waitUntil: 'domcontentloaded',
    });
    const deployForm = formByAction(page, `page=userdata&action=deploy&id=${dataId}`);
    await expect(deployForm).toBeVisible();
    await deployForm.locator('select[name="vps"]').selectOption(String(vpsId));
    await submitForm(deployForm, 'Deploy');
    await expectNotification(page, 'User data deployed');
    await expect(page).toHaveURL(new RegExp(`page=userdata.*action=edit.*id=${dataId}`));

    await page.goto('/?page=userdata&action=list', { waitUntil: 'domcontentloaded' });
    await rowWithText(page, editedLabel)
      .locator(`a[href*="action=delete"][href*="id=${dataId}"]`)
      .click();
    await expectNotification(page, 'User data deleted');
    await expect(rowWithText(page, editedLabel)).toHaveCount(0);

    await logout(page, fixtures.user.username);
  });

  test('admin lifetime, reminder, and console pages render for managed resources', async ({ page }) => {
    requireMiscFixtures();

    await login(page, fixtures.admin);

    await page.goto(`/?page=adminm&action=edit&id=${managed.id}`, {
      waitUntil: 'domcontentloaded',
    });
    const stateForm = formByAction(
      page,
      `page=lifetimes&action=set_state&resource=user&id=${managed.id}`,
    );
    await expect(stateForm.locator('select[name="object_state"]')).toBeVisible();
    await expect(stateForm.locator('input[name="expiration_date"]')).toBeVisible();
    await stateForm.locator('select[name="object_state"]').selectOption('active');
    await stateForm.locator('input[name="expiration_date"]').fill(futureDateTime(35));
    await submitForm(stateForm, 'Go >>');
    await expectNotification(page, 'State set');
    await expect(page).toHaveURL(new RegExp(`page=adminm.*action=edit.*id=${managed.id}`));

    await page.goto(
      `/?page=lifetimes&action=changelog&resource=user&id=${managed.id}&return=%2F%3Fpage%3Dadminm`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(content(page)).toContainText(`State log for user #${managed.id}`);

    await setReminder(page, 'user', managed.id, 'date', futureDate(42));
    await setReminder(page, 'vps', fixtures.vps.fixtures.support.id, 'never');

    const iframeRendered = await expectConsoleIframe(page, fixtures.vps.fixtures.support.id);
    test.skip(!iframeRendered, 'Fixture location has no remote console server');

    for (const label of ['Start', 'Stop', 'Restart', 'Reset', 'Poweroff']) {
      await expect(page.locator('#aside a', { hasText: label }).first()).toBeVisible();
    }
    await expect(page.locator('#aside button', { hasText: 'Generate password' })).toBeVisible();
    await expect(page.locator('#aside select[name="os_template"]')).toBeVisible();
    await expect(page.locator('#aside input[name="root_mountpoint"]')).toBeVisible();
    await expect(page.locator('#boot-button')).toContainText('Boot');

    await logout(page, fixtures.admin.username);
  });

  test('NAS list pages expose user and admin views', async ({ page }) => {
    requireMiscFixtures();

    await login(page, fixtures.user);
    await page.goto('/?page=nas', { waitUntil: 'domcontentloaded' });
    await expect(content(page)).toContainText('Datasets');
    await expect(content(page)).toContainText(storage.datasets.nas_list.name);
    await expect(page.locator('form[name="nas-filter"]')).toHaveCount(0);
    await logout(page, fixtures.user.username);

    await login(page, fixtures.admin);
    await page.goto('/?page=nas&action=list', { waitUntil: 'domcontentloaded' });
    const filter = page.locator('form[name="nas-filter"]').first();
    await expect(filter).toBeVisible();
    await expect(filter.locator('input[name="limit"]')).toBeVisible();
    await expect(filter.locator('input[name="from_id"]')).toBeVisible();
    await expect(filter.locator('input[name="user"]')).toBeVisible();
    await expect(filter.locator('input[name="dataset"]')).toBeVisible();
    await filter.locator('input[name="limit"]').fill('10');
    await filter.locator('input[name="from_id"]').fill('0');
    await filter.locator('input[name="user"]').fill(String(fixtures.user.id));
    await submitForm(filter, 'Show');
    await expect(page).toHaveURL(/page=nas.*action=list/);
    await expect(filter.locator('input[name="user"]')).toHaveValue(String(fixtures.user.id));
    await expect(content(page)).toContainText('Datasets');

    await logout(page, fixtures.admin.username);
  });

  test('redirect helper routes known targets and rejects unsupported paths', async ({ page }) => {
    requireMiscFixtures();

    await page.goto(
      `/?page=redirect&to=payset&from=payment&id=${managed.userPayment.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page).toHaveURL(/page=redirect.*to=payset.*from=payment/);
    await expect(page).not.toHaveURL(/page=adminm.*action=payset/);
    await expect(content(page)).not.toContainText('User payments');
    await expect(content(page)).not.toContainText(managed.username);

    await login(page, fixtures.admin);
    await page.goto(
      `/?page=redirect&to=payset&from=payment&id=${managed.userPayment.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page).toHaveURL(new RegExp(`page=adminm.*action=payset.*id=${managed.id}`));
    await expect(content(page)).toContainText('User payments');
    await expect(content(page)).toContainText(managed.username);

    const hostAddress = networking.hostAddresses.user_ptr;
    await page.goto(
      `/?page=redirect&to=ip_address&from=host_ip_address&id=${hostAddress.id}`,
      { waitUntil: 'domcontentloaded' },
    );
    await expect(page).toHaveURL(
      new RegExp(`page=networking.*action=route_edit.*id=${hostAddress.ipAddressId}`),
    );
    await expect(content(page)).toContainText(hostAddress.routedAddress);
    await expect(formByAction(page, `action=route_edit_user&id=${hostAddress.ipAddressId}`)).toBeVisible();

    await page.goto('/?page=redirect&to=unsupported&from=direct&id=0', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page).toHaveURL(/page=redirect.*to=unsupported.*from=direct/);
    await expect(page).not.toHaveURL(/page=adminm|page=networking|page=payset/);
    await expect(content(page)).not.toContainText('User payments');
    await expect(content(page)).not.toContainText(managed.username);
    await expect(content(page)).not.toContainText(hostAddress.routedAddress);
    await expect(formByAction(page, `action=route_edit_user&id=${hostAddress.ipAddressId}`)).toHaveCount(0);

    await logout(page, fixtures.admin.username);
  });
});
