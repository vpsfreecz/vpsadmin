const { expect } = require('@playwright/test');

function notification(page) {
  return page.locator('#perex');
}

function formByAction(page, actionPart) {
  return page.locator(`form[action*="${actionPart}"]`).first();
}

async function submitForm(form, valuePattern = null) {
  if (valuePattern) {
    const submits = await form.locator('input[type="submit"]').all();

    for (const submit of submits) {
      const value = (await submit.getAttribute('value')) || '';

      if (valuePattern.test(value)) {
        await submit.click();
        return;
      }
    }

    throw new Error(`No submit button matched ${valuePattern}`);
  }

  await form.locator('input[type="submit"]').last().click();
}

async function expectNotification(page, text) {
  await expect(notification(page)).toContainText(text);
}

async function detailValue(page, label) {
  const row = page.locator('table.table-style01 tr', { hasText: `${label}:` }).first();
  await expect(row).toBeVisible();

  return (await row.locator('td').nth(1).innerText()).trim();
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

module.exports = {
  acceptNextDialog,
  detailValue,
  expectNotification,
  formByAction,
  gotoVpsDetail,
  notification,
  submitForm,
  waitForDetailValue,
  waitForVpsTransactionsSettled,
  waitForVpsStatus,
};
