const { expect } = require('@playwright/test');

function notification(page) {
  return page.locator('#perex');
}

function formByAction(page, actionPart, options = {}) {
  const formName = typeof options === 'string' ? options : options.name;
  const namePart = formName ? `[name="${formName}"]` : '';

  return page.locator(`form[action*="${actionPart}"]${namePart}`).first();
}

function formByName(page, name) {
  return page.locator(`form[name="${name}"]`).first();
}

async function submitForm(form, valuePattern = null) {
  const controls = await form
    .locator('input[type="submit"], button[type="submit"], button:not([type])')
    .all();

  if (valuePattern) {
    const pattern = valuePattern instanceof RegExp
      ? valuePattern
      : new RegExp(`^${escapeRegExp(String(valuePattern))}$`);

    for (const control of controls) {
      const value = (await control.getAttribute('value')) || (await control.innerText()).trim();

      if (pattern.test(value)) {
        await control.click();
        return;
      }
    }

    throw new Error(`No submit button matched ${pattern}`);
  }

  if (controls.length === 0) {
    throw new Error('No submit button found');
  }

  await controls[controls.length - 1].click();
}

async function expectNotification(page, text) {
  await expect(notification(page)).toContainText(text);
}

async function detailValue(page, label) {
  const row = detailRow(page, label);
  await expect(row).toBeVisible();

  return (await row.locator('td').nth(1).innerText()).trim();
}

function detailRow(page, label) {
  return page.locator('table.table-style01 tr', { hasText: new RegExp(`^\\s*${escapeRegExp(label)}:?\\s*`) }).first();
}

async function detailRows(page, table = page.locator('table.table-style01').first()) {
  const rows = await table.locator('tr').all();
  const ret = {};

  for (const row of rows) {
    const cells = await row.locator('td').allInnerTexts();

    if (cells.length < 2) {
      continue;
    }

    const key = cells[0].replace(/:\s*$/, '').trim();
    if (key) {
      ret[key] = cells.slice(1).join('\n').trim();
    }
  }

  return ret;
}

async function gotoVpsDetail(page, vpsId) {
  await page.goto(`/?page=adminvps&action=info&veid=${vpsId}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect(page.locator('#content-in h1')).toContainText(`VPS #${vpsId}`);
}

async function waitForDetailValue(page, vpsId, label, pattern, options = {}) {
  const timeout = options.timeout || 10 * 60 * 1000;

  await expect
    .poll(
      async () => {
        await gotoVpsDetail(page, vpsId);
        return detailValue(page, label);
      },
      {
        timeout,
        intervals: [1000, 2000, 5000],
      },
    )
    .toMatch(pattern);
}

async function waitForVpsStatus(page, vpsId, expected, options = {}) {
  await waitForDetailValue(page, vpsId, 'Status', new RegExp(`\\b${expected}\\b`), options);
}

async function waitForVpsTransactionsSettled(page, vpsId, options = {}) {
  const timeout = options.timeout || 10 * 60 * 1000;
  const pendingPattern = /\b(queued|rollbacking)\b/;
  const failedPattern = /\b(failed|fatal)\b/;

  await expect
    .poll(
      async () => {
        await page.goto(`/?page=transactions&class_name=Vps&row_id=${vpsId}`, {
          waitUntil: 'domcontentloaded',
        });

        const rows = page.locator('tr', {
          has: page.locator('a[href*="page=transactions&chain="]'),
        });
        const texts = await rows.allInnerTexts();

        const failed = texts.find((text) => failedPattern.test(text));
        if (failed) {
          throw new Error(`VPS transaction failed: ${failed}`);
        }

        return texts.some((text) => pendingPattern.test(text)) ? 'pending' : 'settled';
      },
      {
        timeout,
        intervals: [1000, 2000, 5000],
      },
    )
    .toBe('settled');
}

async function acceptNextDialog(page) {
  page.once('dialog', async (dialog) => {
    await dialog.accept();
  });
}

async function withAcceptedDialog(page, callback) {
  const dialogPromise = page.waitForEvent('dialog');
  const result = await callback();
  const dialog = await dialogPromise;
  await dialog.accept();
  return result;
}

async function csrfTokenFromForm(form) {
  const token = await form.locator('input[name="csrf_token"]').first().getAttribute('value');

  if (!token) {
    throw new Error('Form does not contain a CSRF token');
  }

  return token;
}

async function csrfTokenFromLink(page, locatorOrHref) {
  let href;

  if (typeof locatorOrHref === 'string') {
    href = locatorOrHref;
  } else {
    href = await locatorOrHref.getAttribute('href');
  }

  if (!href) {
    throw new Error('Link does not contain an href');
  }

  const url = new URL(href, page.url());
  const token = url.searchParams.get('t');

  if (!token) {
    throw new Error(`Link does not contain a CSRF token: ${href}`);
  }

  return token;
}

async function csrfParamsFromForm(form) {
  return {
    csrf_token: await csrfTokenFromForm(form),
  };
}

async function visibleTransactionChainIds(page) {
  const links = await page
    .locator('a[href*="page=transactions"][href*="chain="]')
    .evaluateAll((els) => els.map((el) => el.getAttribute('href')));
  const ids = new Set();

  for (const href of links) {
    if (!href) {
      continue;
    }

    const url = new URL(href, page.url());
    const id = url.searchParams.get('chain');

    if (id) {
      ids.add(id);
    }
  }

  return Array.from(ids);
}

async function waitForTransactionChainsSettled(page, options = {}) {
  const timeout = options.timeout || 10 * 60 * 1000;
  const pendingStates = options.pendingStates || ['queued', 'rollbacking'];
  const failedStates = options.failedStates || ['failed'];
  const chainIds = options.chainIds || await visibleTransactionChainIds(page);

  if (chainIds.length === 0) {
    throw new Error('No visible transaction chains found');
  }

  await expect
    .poll(
      async () => {
        const states = [];

        for (const chainId of chainIds) {
          await page.goto(`/?page=transactions&chain=${chainId}`, {
            waitUntil: 'domcontentloaded',
          });

          const state = (await detailValue(page, 'State')).toLowerCase();
          states.push(`${chainId}:${state}`);

          if (!options.allowFailed && failedStates.includes(state)) {
            throw new Error(`Transaction chain ${chainId} failed`);
          }
        }

        return states.some((entry) => pendingStates.some((state) => entry.endsWith(`:${state}`)))
          ? 'pending'
          : 'settled';
      },
      {
        timeout,
        intervals: [1000, 2000, 5000],
      },
    )
    .toBe('settled');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  acceptNextDialog,
  csrfParamsFromForm,
  csrfTokenFromForm,
  csrfTokenFromLink,
  detailRow,
  detailRows,
  detailValue,
  expectNotification,
  formByAction,
  formByName,
  gotoVpsDetail,
  notification,
  submitForm,
  visibleTransactionChainIds,
  waitForDetailValue,
  waitForTransactionChainsSettled,
  waitForVpsTransactionsSettled,
  waitForVpsStatus,
  withAcceptedDialog,
};
