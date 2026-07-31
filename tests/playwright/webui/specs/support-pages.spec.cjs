const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  acceptNextDialog,
  expectNotification,
  formByAction,
  submitForm,
} = require('../lib/pages/webui.cjs');
const {
  hrefParam,
  linkWithParams,
  rowWithText,
  selectIfPresent,
  setCheckboxIfPresent,
  submitMonitoringAction,
} = require('../lib/pages/support.cjs');

const fixtures = readFixtures();
const support = fixtures.support;
const languageFlag = (page, locale) =>
  page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`);

async function switchLanguage(page, locale) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
    languageFlag(page, locale).click(),
  ]);
}

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

function notificationSidebarLinks(page) {
  return page
    .locator('#aside h3', { hasText: 'Notifications' })
    .locator('xpath=following-sibling::ul[1]/li/a');
}

function notificationDeliveryTable(page) {
  return page
    .locator('table.table-style01')
    .filter({ has: page.locator('th', { hasText: 'Delivery' }) })
    .filter({ has: page.locator('th', { hasText: 'Next retry' }) })
    .last();
}

async function routeDomIds(page) {
  return page
    .locator('#notification-routes-table tr[id^="route_"]')
    .evaluateAll((rows) => rows.map((row) => row.id));
}

async function rootRouteIds(page) {
  const ids = await routeDomIds(page);

  return ids
    .map((id) => {
      const match = id.match(/^route_(\d+)_p_root$/);
      return match ? match[1] : null;
    })
    .filter(Boolean);
}

async function dragBetween(page, source, target, targetVerticalRatio = 0.5) {
  const sourceBox = await source.boundingBox();
  const targetBox = await target.boundingBox();

  if (!sourceBox || !targetBox) {
    throw new Error('Unable to resolve drag source or target box');
  }

  await page.mouse.move(
    sourceBox.x + sourceBox.width / 2,
    sourceBox.y + sourceBox.height / 2,
  );
  await page.mouse.down();
  await page.mouse.move(
    targetBox.x + targetBox.width / 2,
    targetBox.y + targetBox.height * targetVerticalRatio,
    { steps: 8 },
  );
  await page.mouse.up();
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

  test('user notification settings and test events are wired', async ({ page }) => {
    await login(page, fixtures.user);

    await page.goto('/?page=notifications', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Event log');

    await page.goto('/?page=notifications&action=event_types', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Event types');
    await expect(content(page).locator('details summary').first()).toBeVisible();
    const testEventType = content(page).locator('#event-type-user-test_notification');
    await expect(testEventType).toHaveCount(1);
    const testEventFields = testEventType.locator('table.table-style01').filter({
      has: page.locator('th', { hasText: /^Field$/ }),
    });
    await expect(testEventFields).toHaveCount(1);
    await expect(testEventFields).toContainText('Field');
    await expect(testEventFields).toContainText('Type');
    await expect(testEventFields).toContainText('Example');
    await expect(testEventFields).toContainText('Meaning');
    await expect(testEventFields).toContainText('note');

    await page.goto('/?page=notifications&action=events', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Event log');
    const eventLogFilter = formByName(page, 'notification-events');
    await expect(eventLogFilter).toBeVisible();
    await expect(eventLogFilter.locator('select[name="delivery_action"]')).toBeVisible();
    await expect(eventLogFilter.locator('select[name="action"]')).toHaveCount(0);
    await expect(notificationSidebarLinks(page)).toHaveText([
      'Event log',
      'Routes',
      'Receivers',
      'Targets',
      'Time intervals',
      'Limits',
      'Event types',
      'Test event',
    ]);

    await page.goto('/?page=notifications&action=delivery_queue', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#perex')).toContainText('Access forbidden');
    await expect(page.locator('#perex')).toContainText(
      'Only administrators can view notification delivery queues.',
    );

    await page.goto('/?page=notifications&action=delivery_log', {
      waitUntil: 'domcontentloaded',
    });
    await expect(page.locator('#perex')).toContainText('Access forbidden');

    await page.goto('/?page=notifications&action=receivers', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Notification receivers');
    await expect(content(page)).toContainText(/Default|Do not notify/);

    const receiverLabel = 'Webui notification receiver';
    const receiverForm = formByAction(page, 'action=receiver_new');
    await receiverForm.locator('input[name="label"]').fill(receiverLabel);
    await submitForm(receiverForm, 'Add');
    await expectNotification(page, 'Receiver added');

    const receiverRow = rowWithText(page, receiverLabel);
    await expect(receiverRow).toBeVisible();
    const receiverEditLink = linkWithParams(receiverRow, { action: 'receiver_edit' });
    const receiverId = await hrefParam(receiverEditLink, 'id', page.url());

    await receiverEditLink.click();
    await expect(heading(page)).toContainText(`Notification receiver #${receiverId}`);
    await expect(content(page)).toContainText('Targets');

    await page.goto(`/?page=notifications&action=target_new&receiver=${receiverId}&type=email`, {
      waitUntil: 'domcontentloaded',
    });
    const emailTargetForm = formByAction(page, 'action=target_new');
    await expect(emailTargetForm).toBeVisible();
    await expect(emailTargetForm.locator('input[name="template_name"]')).toHaveCount(0);

    await page.goto(`/?page=notifications&action=receiver_edit&id=${receiverId}`, {
      waitUntil: 'domcontentloaded',
    });
    await linkWithParams(content(page), {
      action: 'target_new',
      receiver: receiverId,
    }).click();
    await expect(heading(page)).toContainText('Add notification target');
    const targetTypeForm = formByName(page, 'notification-target-type');
    await targetTypeForm.locator('select[name="type"]').selectOption('webhook');
    await submitForm(targetTypeForm, 'Continue');

    const targetForm = formByAction(page, 'action=target_new');
    await expect(targetForm).toBeVisible();
    await expect(content(page)).toContainText('Webhook URL');
    await expect(content(page)).toContainText('X-VpsAdmin-Signature-256');
    await expect(targetForm.locator('input[name="target_value"]')).toHaveAttribute('size', '50');
    await expect(targetForm.locator('input[name="secret"]')).toHaveAttribute('type', 'text');
    await targetForm.locator('input[name="label"]').fill('Webui webhook target');
    await targetForm.locator('input[name="target_value"]').fill('https://example.test/webui');
    await targetForm.locator('input[name="secret"]').fill('webui-secret');
    await submitForm(targetForm, 'Add');
    await expectNotification(page, 'Target added');
    await expect(heading(page)).toContainText(`Notification receiver #${receiverId}`);
    const newTargetRow = rowWithText(page, 'Webui webhook target');
    await expect(newTargetRow).toBeVisible();
    const newTargetEditLink = linkWithParams(newTargetRow, { action: 'target_edit' });
    const notificationTargetId = await hrefParam(newTargetEditLink, 'id', page.url());
    await newTargetEditLink.click();
    await expect(heading(page)).toContainText(`Notification target #${notificationTargetId}`);

    const targetEditForm = formByAction(page, 'action=target_edit');
    await expect(targetEditForm.locator('select[name="action"]')).toHaveCount(0);
    await targetEditForm.locator('input[name="label"]').fill('Webui webhook target edited');
    await submitForm(targetEditForm, 'Save');
    await expectNotification(page, 'Target updated');

    const intervalName = 'Webui always-active interval';
    await page.goto('/?page=notifications&action=time_intervals', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Notification time intervals');
    await expect(content(page).locator('[data-vpsadmin-doc-id="notifications.time-intervals"]'))
      .toBeVisible();
    await content(page).getByRole('link', { name: 'Add time interval' }).click();
    const intervalForm = formByAction(page, 'action=time_interval_new');
    await expect(page.locator('[data-vpsadmin-doc-id="notifications.time-interval-form"]'))
      .toBeVisible();
    await intervalForm.locator('input[name="name"]').fill(intervalName);
    const timeZoneSelect = intervalForm.locator('select[name="time_zone"]');
    await expect(timeZoneSelect).toHaveValue('UTC');
    await expect(timeZoneSelect.locator('option[value="Europe/Prague"]')).toHaveCount(1);
    await expect(intervalForm.locator('input[name="time_zone"]')).toHaveCount(0);
    await timeZoneSelect.selectOption('UTC');
    await intervalForm.locator('#notification-time-interval-add-spec').click();
    const intervalSpecs = intervalForm.locator('.notification-time-interval-spec');
    await expect(intervalSpecs).toHaveCount(2);
    await expect(intervalSpecs.nth(0).locator('.notification-time-interval-spec-separator'))
      .toBeHidden();
    await expect(intervalSpecs.nth(1).locator('.notification-time-interval-spec-separator'))
      .toBeVisible();
    await intervalSpecs.nth(0).locator('.notification-time-interval-remove').click();
    await expect(intervalSpecs).toHaveCount(1);
    await expect(intervalSpecs.nth(0).locator('.notification-time-interval-spec-separator'))
      .toBeHidden();
    await intervalSpecs.nth(0).locator('input[name$="[times]"]').fill('00:00-24:00');
    await intervalSpecs.nth(0).locator('input[name$="[weekdays]"]').fill('');
    await submitForm(intervalForm, 'Add');
    await expectNotification(page, 'Time interval added');
    const intervalId = new URL(page.url()).searchParams.get('id');
    expect(intervalId).toMatch(/^\d+$/);

    await page.goto(`/?page=notifications&action=receiver_edit&id=${receiverId}`, {
      waitUntil: 'domcontentloaded',
    });
    const targetRow = rowWithText(page, 'Webui webhook target edited');
    await expect(targetRow).toBeVisible();
    await expect(targetRow).toContainText('Webhook');
    await expect(targetRow).toContainText('https://example.test/webui');
    const targetEditLink = linkWithParams(targetRow, {
      action: 'target_edit',
      id: notificationTargetId,
    });
    await expect(targetEditLink).toBeVisible();
    const targetEventLink = linkWithParams(targetRow, {
      action: 'events',
      notification_target_id: notificationTargetId,
    });
    const receiverTargetId = await hrefParam(targetEventLink, 'notification_receiver_target_id', page.url());

    await page.goto('/?page=notifications&action=routes', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Notification routes');
    await expect(content(page)).toContainText('Default route');
    const defaultRouteRow = rowWithText(page, 'Default route');
    const defaultRouteEditLink = linkWithParams(defaultRouteRow, { action: 'route_edit' });
    const defaultRouteId = await hrefParam(defaultRouteEditLink, 'id', page.url());
    await expect(linkWithParams(defaultRouteRow, {
      action: 'route_new',
      parent: defaultRouteId,
    })).toBeVisible();

    await defaultRouteEditLink.click();
    await expect(heading(page)).toContainText(`Notification route #${defaultRouteId}`);
    await expect(content(page)).toContainText('Subroutes');
    await expect(content(page)).toContainText('Matchers');

    await page.goto('/?page=notifications&action=routes', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Notification routes');

    const routeLabel = 'Webui notification route';
    await content(page)
      .locator('a[href*="action=route_new"]')
      .filter({ hasText: 'Add route' })
      .last()
      .click();
    await expect(heading(page)).toContainText('Add notification route');
    const routeForm = formByAction(page, 'action=route_new');
    await expect(routeForm).toBeVisible();
    await routeForm.locator('input[name="label"]').fill(routeLabel);
    await routeForm.locator('select[name="event_type"]').selectOption('user.test_notification');
    await routeForm.locator('select[name="notification_receiver_id"]').selectOption(receiverId);
    await submitForm(routeForm, 'Add');
    await expectNotification(page, 'Route added');
    await expect(heading(page)).toContainText('Notification route #');
    await expect(content(page)).toContainText('Subroutes');
    await expect(content(page)).toContainText('Matchers');
    await expect(content(page)).toContainText('Receiver');
    const routeId = new URL(page.url()).searchParams.get('id');

    await page.goto('/?page=notifications&action=routes', {
      waitUntil: 'domcontentloaded',
    });
    const routeRow = rowWithText(page, routeLabel);
    await expect(routeRow).toBeVisible();
    await expect(routeRow).toContainText(receiverLabel);
    const routeEditLink = linkWithParams(routeRow, { action: 'route_edit' });
    await expect(routeEditLink).toHaveAttribute('href', new RegExp(`id=${routeId}`));

    await routeEditLink.click();
    await expect(heading(page)).toContainText(`Notification route #${routeId}`);
    await expect(content(page)).toContainText('Matchers');
    await expect(content(page)).toContainText('Receiver');
    const assignmentForm = formByAction(page, 'action=route_time_intervals_save');
    await expect(page.locator('[data-vpsadmin-doc-id="notifications.route-time-intervals"]'))
      .toBeVisible();
    await assignmentForm.locator('select[name="event_time_interval"]').selectOption(intervalId);
    await assignmentForm.locator('select[name="mode"]').selectOption('active');
    await submitForm(assignmentForm, 'Assign interval');
    await expectNotification(page, 'Time interval assigned');
    await expect(rowWithText(page, intervalName)).toContainText('Active interval');

    await linkWithParams(content(page), {
      action: 'matcher_new',
      route: routeId,
    }).click();
    await expect(heading(page)).toContainText('Add matcher');
    await expect(formByName(page, 'notification-matcher-event-type')).toHaveCount(0);
    const matcherForm = formByAction(page, 'action=matcher_new');
    await expect(matcherForm.locator('select[name="operator"]')).toContainText('== (equals)');
    await matcherForm.locator('select[name="field"]').selectOption('note');
    await matcherForm.locator('select[name="operator"]').selectOption('==');
    await matcherForm.locator('input[name="value"]').fill('testing notification routing');
    await submitForm(matcherForm, 'Add');
    await expectNotification(page, 'Matcher added');
    const matcherRow = content(page).locator('table.table-style01 tr').filter({
      has: page.locator('code', { hasText: /^note$/ }),
    }).first();
    await expect(matcherRow).toBeVisible();
    await expect(matcherRow.locator('select[name*="[field]"]')).toHaveCount(0);
    await expect(matcherRow).toContainText('note');

    await page.goto('/?page=notifications&action=test', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Test notification event');
    const testForm = formByAction(page, 'action=test');
    const subject = 'Webui notification test event';
    await testForm.locator('input[name="subject"]').fill(subject);
    await submitForm(testForm, 'Create event');
    await expectNotification(page, 'Test event created');
    await expect(heading(page)).toContainText('Event #');
    await expect(content(page)).toContainText(subject);
    await expect(content(page)).toContainText('Deliveries');
    await expect(content(page)).toContainText('webhook');
    const matchedRoutesHeading = page.locator(
      '[data-vpsadmin-doc-id="notifications.event-route-matches"]',
    );
    await expect(matchedRoutesHeading).toBeVisible();
    const matchedRoutes = matchedRoutesHeading.locator(
      'xpath=following-sibling::table[contains(@class, "table-style01")][1]',
    );
    await expect(matchedRoutes).toBeVisible();
    const matchedRouteRow = matchedRoutes.locator('tr', { hasText: routeLabel }).first();
    await expect(matchedRouteRow).toContainText('active');
    await expect(matchedRouteRow).toContainText(intervalName);
    const payloadRow = rowWithText(page, 'Payload');
    await expect(payloadRow.locator('pre')).toContainText('"note"');
    await expect(payloadRow.locator('pre')).toContainText('testing notification routing');
    const eventDeliveryRow = rowWithText(page, 'webhook');
    await expect(eventDeliveryRow).toContainText(receiverLabel);
    await expect(eventDeliveryRow).toContainText('Webui webhook target edited');
    await expect(linkWithParams(eventDeliveryRow, {
      action: 'target_edit',
      id: notificationTargetId,
    })).toBeVisible();

    const deliveryDetailLink = linkWithParams(content(page), {
      action: 'delivery_show',
    });
    await deliveryDetailLink.first().click();
    await expect(heading(page)).toContainText('Event delivery #');
    await expect(content(page)).toContainText('Webhook');
    await expect(content(page)).toContainText('Request payload');
    await expect(content(page)).toContainText('user.test_notification');
    await expect(content(page)).toContainText(receiverLabel);
    await expect(content(page)).toContainText('Webui webhook target edited');
    await expect(linkWithParams(content(page), {
      action: 'receiver_edit',
      id: receiverId,
    })).toBeVisible();
    await expect(linkWithParams(content(page), {
      action: 'target_edit',
      id: notificationTargetId,
    })).toBeVisible();
    await expect(content(page)).toContainText('Delivery attempts');

    await page.goto('/?page=notifications&action=receivers', {
      waitUntil: 'domcontentloaded',
    });
    const receiverEventLink = linkWithParams(rowWithText(page, receiverLabel), {
      action: 'events',
      notification_receiver_id: receiverId,
    });
    await receiverEventLink.click();
    await expect(heading(page)).toContainText('Event log');
    await expect(formByName(page, 'notification-events').locator('input[name="notification_receiver_id"]')).toHaveValue(receiverId);
    await expect(content(page)).toContainText(subject);

    await page.goto(`/?page=notifications&action=receiver_edit&id=${receiverId}`, {
      waitUntil: 'domcontentloaded',
    });
    const receiverTargetEventLink = linkWithParams(rowWithText(page, 'Webui webhook target edited'), {
      action: 'events',
      notification_receiver_target_id: receiverTargetId,
    });
    await receiverTargetEventLink.click();
    await expect(heading(page)).toContainText('Event log');
    await expect(formByName(page, 'notification-events').locator('input[name="notification_receiver_target_id"]')).toHaveValue(receiverTargetId);
    await expect(content(page)).toContainText(subject);

    const childRouteLabel = 'Webui notification child route';
    await page.goto(`/?page=notifications&action=route_new&parent=${routeId}`, {
      waitUntil: 'domcontentloaded',
    });
    const childRouteForm = formByAction(page, 'action=route_new');
    await childRouteForm.locator('input[name="label"]').fill(childRouteLabel);
    await childRouteForm.locator('select[name="event_type"]').selectOption('user.test_notification');
    await submitForm(childRouteForm, 'Add');
    await expectNotification(page, 'Route added');
    const childRouteId = new URL(page.url()).searchParams.get('id');

    await page.goto('/?page=notifications&action=routes', {
      waitUntil: 'domcontentloaded',
    });
    const routeTable = page.locator('#notification-routes-table');
    const parentRow = routeTable.locator(`#route_${routeId}_p_root`);
    const childRow = routeTable.locator(`#route_${childRouteId}_p_${routeId}`);
    const defaultRow = routeTable.locator(`#route_${defaultRouteId}_p_root`);
    await expect(parentRow).toBeVisible();
    await expect(childRow).toBeVisible();
    await expect(defaultRow).toBeVisible();
    const idsWithChild = await routeDomIds(page);
    expect(idsWithChild[idsWithChild.indexOf(`route_${routeId}_p_root`) + 1])
      .toBe(`route_${childRouteId}_p_${routeId}`);

    const handle = parentRow.locator('.notification-drag-handle');
    await expect(handle).toHaveCSS('cursor', 'move');
    await expect(parentRow.locator('td').nth(1)).not.toHaveCSS('cursor', 'move');

    const orderBeforeCellDrag = await routeDomIds(page);
    await dragBetween(page, parentRow.locator('td').nth(1), defaultRow, 0.9);
    expect(await routeDomIds(page)).toEqual(orderBeforeCellDrag);

    const rootsBeforeHandleDrag = await rootRouteIds(page);
    expect(rootsBeforeHandleDrag.indexOf(routeId)).toBeLessThan(
      rootsBeforeHandleDrag.indexOf(defaultRouteId),
    );
    const reorderResponse = page.waitForResponse(
      (response) => response.url().includes('action=route_reorder')
        && response.request().method() === 'POST',
    );
    await dragBetween(page, handle, defaultRow, 0.9);
    await reorderResponse;
    await expect
      .poll(async () => {
        const ids = await rootRouteIds(page);
        return ids.indexOf(routeId) > ids.indexOf(defaultRouteId);
      })
      .toBe(true);
    const idsAfterDrag = await routeDomIds(page);
    expect(idsAfterDrag[idsAfterDrag.indexOf(`route_${routeId}_p_root`) + 1])
      .toBe(`route_${childRouteId}_p_${routeId}`);

    await page.reload({ waitUntil: 'domcontentloaded' });
    const idsAfterReload = await routeDomIds(page);
    expect(idsAfterReload[idsAfterReload.indexOf(`route_${routeId}_p_root`) + 1])
      .toBe(`route_${childRouteId}_p_${routeId}`);
    await expect
      .poll(async () => {
        const ids = await rootRouteIds(page);
        return ids.indexOf(routeId) > ids.indexOf(defaultRouteId);
      })
      .toBe(true);

    const createdRouteRow = rowWithText(page, routeLabel);
    await expect(createdRouteRow).toBeVisible();
    await acceptNextDialog(page);
    await linkWithParams(createdRouteRow, {
      action: 'route_delete',
      id: routeId,
    }).click();
    await expectNotification(page, 'Route deleted');

    await page.goto('/?page=notifications&action=time_intervals', {
      waitUntil: 'domcontentloaded',
    });
    const intervalRow = rowWithText(page, intervalName);
    await expect(intervalRow).toBeVisible();
    await acceptNextDialog(page);
    await linkWithParams(intervalRow, {
      action: 'time_interval_delete',
      id: intervalId,
    }).click();
    await expectNotification(page, 'Time interval deleted');

    await page.goto('/?page=notifications&action=receivers', {
      waitUntil: 'domcontentloaded',
    });
    const createdReceiverRow = rowWithText(page, receiverLabel);
    await expect(createdReceiverRow).toBeVisible();
    await acceptNextDialog(page);
    await linkWithParams(createdReceiverRow, {
      action: 'receiver_delete',
      id: receiverId,
    }).click();
    await expectNotification(page, 'Receiver deleted');

    await logout(page, fixtures.user.username);
  });

  test('admin notification delivery queues are wired', async ({ page }) => {
    await login(page, fixtures.admin);

    await page.goto('/?page=notifications&action=events', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Event log');
    await expect(notificationSidebarLinks(page)).toHaveText([
      'Event log',
      'Delivery queue',
      'Delivery log',
      'Routes',
      'Receivers',
      'Targets',
      'Time intervals',
      'Limits',
      'Event types',
      'Test event',
    ]);

    await page.goto('/?page=notifications&action=delivery_queue', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Delivery queue');
    await expect(formByName(page, 'notification-deliveries')).toBeVisible();
    await expect(notificationDeliveryTable(page).locator('th')).toHaveText([
      'Delivery',
      'Event',
      'User',
      'VPS',
      'Receiver',
      'Target',
      'State',
      'Attempts',
      'Released',
      'Last attempt',
      'Next retry',
      '',
    ]);

    await page.goto('/?page=notifications&action=delivery_log', {
      waitUntil: 'domcontentloaded',
    });
    await expect(heading(page)).toContainText('Delivery log');
    await expect(formByName(page, 'notification-deliveries')).toBeVisible();
    await expect(notificationDeliveryTable(page).locator('th')).toHaveText([
      'Delivery',
      'Event',
      'User',
      'VPS',
      'Receiver',
      'Target',
      'State',
      'Attempts',
      'Released',
      'Last attempt',
      'Next retry',
      '',
    ]);

    await logout(page, fixtures.admin.username);
  });

  test('user OOM reports and notification route redirect are wired', async ({ page }) => {
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
    await expect(page).toHaveURL(/page=notifications/);
    await expect(page).toHaveURL(/action=routes/);
    await expectNotification(page, 'OOM report rules moved');
    await expect(heading(page)).toContainText('Notification routes');

    await logout(page, fixtures.user.username);
  });

  test('admin OOM filters, fields, and notification route redirect are wired', async ({ page }) => {
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

    await page.goto(`/?page=oom_reports&action=rule_list&vps=${s.vps.id}`, {
      waitUntil: 'domcontentloaded',
    });
    await expect(page).toHaveURL(/page=notifications/);
    await expect(page).toHaveURL(/action=routes/);
    await expect(page).toHaveURL(new RegExp(`user=${fixtures.user.id}`));
    await expectNotification(page, 'OOM report rules moved');
    await expect(heading(page)).toContainText('Notification routes');

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

    await switchLanguage(page, 'cs_CZ.utf8');
    try {
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

      const localizedFilter = formByName(page, 'monitoring-list');
      await expect(
        localizedFilter.locator('select[name="state"] option:checked'),
      ).toHaveText('potvrzeno');
      await expect(rowWithText(page, showEvent.label)).toContainText('potvrzeno');

      await page.goto(`/?page=monitoring&action=show&id=${showEvent.id}`, {
        waitUntil: 'domcontentloaded',
      });
      const stateRow = content(page).locator('tr').filter({ hasText: 'Stav:' }).first();
      await expect(stateRow.locator('td')).toHaveText(['Stav:', 'potvrzeno']);
    } finally {
      await switchLanguage(page, 'en_US.utf8');
      await logout(page, fixtures.user.username);
    }
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
