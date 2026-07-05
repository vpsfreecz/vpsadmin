const { expect } = require('@playwright/test');

const { submitForm } = require('./webui.cjs');

function chainHref(chainId) {
  return `?page=transactions&chain=${chainId}`;
}

function transactionDetailsHref(chainId, transactionId) {
  return `?page=transactions&chain=${chainId}&transaction=${transactionId}&details=1`;
}

function chainFilterForm(page) {
  return page.locator('form[name="vps-filter"]').first();
}

function transactionFilterForm(page) {
  return page.locator('form[name="transaction-filter"]').first();
}

function chainRow(page, chainId) {
  return page
    .locator('#content-in table.table-style01 tr', {
      has: page.locator(`a[href*="page=transactions"][href*="chain=${chainId}"]`),
    })
    .first();
}

function transactionRow(page, chainId, transactionId) {
  return page
    .locator('#content-in table.table-style01 tr', {
      has: page.locator(
        `a[href*="chain=${chainId}"][href*="transaction=${transactionId}"][href*="details=1"]`,
      ),
    })
    .first();
}

async function gotoTransactionList(page, params = {}) {
  const query = new URLSearchParams({ page: 'transactions' });

  for (const [key, value] of Object.entries(params)) {
    query.set(key, String(value));
  }

  await page.goto(`/?${query.toString()}`, { waitUntil: 'domcontentloaded' });
  await expect(chainFilterForm(page)).toBeVisible();
}

async function openChain(page, chainId) {
  await page.goto(`/${chainHref(chainId)}`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#content-in')).toContainText(`Transaction chain #${chainId}`);
}

async function submitChainFilter(page, values) {
  const form = chainFilterForm(page);
  await expect(form).toBeVisible();

  for (const [name, value] of Object.entries(values)) {
    if (name === 'state') {
      await form.locator('select[name="state"]').selectOption(String(value));
    } else {
      await form.locator(`input[name="${name}"]`).fill(String(value));
    }
  }

  await submitForm(form);
}

async function submitTransactionFilter(page, values, options = {}) {
  const form = transactionFilterForm(page);
  await expect(form).toBeVisible();

  for (const [name, value] of Object.entries(values)) {
    if (name === 'node' || name === 'done') {
      await form.locator(`select[name="${name}"]`).selectOption(String(value));
    } else {
      await form.locator(`input[name="${name}"]`).fill(String(value));
    }
  }

  if (options.details) {
    await form.locator('input[name="details"]').check();
  }

  await submitForm(form);
}

module.exports = {
  chainFilterForm,
  chainHref,
  chainRow,
  gotoTransactionList,
  openChain,
  submitChainFilter,
  submitTransactionFilter,
  transactionDetailsHref,
  transactionFilterForm,
  transactionRow,
};
