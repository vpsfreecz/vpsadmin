const { test, expect } = require('@playwright/test');

const { readFixtures } = require('../lib/fixtures.cjs');
const { login, logout } = require('../lib/pages/auth.cjs');
const {
  chainFilterForm,
  chainRow,
  gotoTransactionList,
  openChain,
  submitChainFilter,
  submitTransactionFilter,
  transactionFilterForm,
  transactionRow,
} = require('../lib/pages/transactions.cjs');

const fixtures = readFixtures();
const states = ['queued', 'done', 'rollbacking', 'failed'];
const languageFlag = (page, locale) =>
  page.locator(`#langbox a[href*="newlang=${encodeURIComponent(locale)}"]`);

async function switchLanguage(page, locale) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
    languageFlag(page, locale).click(),
  ]);
}

test('user can open transaction state-filtered lists and chain details', async ({ page }) => {
  await login(page, fixtures.user);

  for (const state of states) {
    const chain = fixtures.transactions.states[state];
    await gotoTransactionList(page, {
      state,
      name: chain.name,
    });

    const form = chainFilterForm(page);
    await expect(form.locator('select[name="state"]')).toHaveValue(state);
    await expect(form.locator('input[name="name"]')).toHaveValue(chain.name);

    const row = chainRow(page, chain.id);
    await expect(row).toBeVisible();
    await expect(row).toContainText(chain.label);
    await expect(row).toContainText(chain.state);
    await expect(row).toContainText(`${chain.progress} (`);

    await row.locator(`a[href*="page=transactions"][href*="chain=${chain.id}"]`).click();
    await expect(page.locator('#content-in')).toContainText(`Transaction chain #${chain.id}`);
    await expect(page.locator('#content-in')).toContainText(chain.name);
    await expect(transactionFilterForm(page)).toBeVisible();
  }

  await logout(page, fixtures.user.username);
});

test('user can filter own transaction chains and transactions', async ({ page }) => {
  const chain = fixtures.transactions.states.done;

  await login(page, fixtures.user);
  await gotoTransactionList(page);

  await submitChainFilter(page, {
    name: chain.name,
    class_name: 'User',
    row_id: fixtures.user.id,
  });

  const row = chainRow(page, chain.id);
  await expect(row).toBeVisible();
  await expect(row).toContainText(chain.label);
  await expect(row).toContainText(chain.state);

  await openChain(page, chain.id);
  await submitTransactionFilter(page, {
    transaction: chain.transactionId,
    node: fixtures.node.id,
    type: chain.transactionType,
    done: chain.transactionDone,
    success: chain.transactionSuccess,
  });

  const txRow = transactionRow(page, chain.id, chain.transactionId);
  await expect(txRow).toBeVisible();
  await expect(txRow).toContainText(chain.transactionName);
  await expect(txRow).toContainText(chain.transactionDone);
  await expect(txRow).toContainText(String(chain.transactionSuccess));

  await logout(page, fixtures.user.username);
});

test('admin sees transaction user filters, session links, and detailed payloads', async ({
  page,
}) => {
  const chain = fixtures.transactions.states.done;

  await login(page, fixtures.admin);
  await gotoTransactionList(page, {
    user: fixtures.user.id,
    user_session: fixtures.transactions.userSession.id,
    name: chain.name,
  });

  const form = chainFilterForm(page);
  await expect(form.locator('input[name="user"]')).toHaveValue(String(fixtures.user.id));
  await expect(form.locator('input[name="user_session"]')).toHaveValue(
    String(fixtures.transactions.userSession.id),
  );

  const row = chainRow(page, chain.id);
  await expect(row).toBeVisible();
  await expect(row).toContainText(fixtures.user.username);
  await expect(row).toContainText(chain.label);

  await openChain(page, chain.id);
  await expect(page.locator('#content-in')).toContainText(fixtures.user.username);
  await expect(page.locator('#content-in')).toContainText(fixtures.transactions.userSession.label);

  await submitTransactionFilter(
    page,
    {
      transaction: chain.transactionId,
      node: fixtures.node.id,
      type: chain.transactionType,
      done: chain.transactionDone,
      success: chain.transactionSuccess,
    },
    { details: true },
  );

  const txRow = transactionRow(page, chain.id, chain.transactionId);
  await expect(txRow).toBeVisible();
  await expect(txRow).toContainText(`${chain.transactionName} (${chain.transactionType})`);
  await expect(page.locator('#content-in')).toContainText('Input');
  await expect(page.locator('#content-in')).toContainText('Output');
  await expect(page.locator('#content-in')).toContainText(chain.fixture);

  await logout(page, fixtures.admin.username);
});

test('user sees localized transaction chain labels and concerns', async ({ page }) => {
  const chain = fixtures.transactions.states.done;

  await login(page, fixtures.user);
  try {
    await switchLanguage(page, 'cs_CZ.utf8');

    await gotoTransactionList(page, { name: chain.name });
    const row = chainRow(page, chain.id);
    await expect(row).toBeVisible();
    await expect(row).toContainText('Uživatel');
    await expect(row).toContainText('Nové přihlášení');

    await page.goto(`/?page=transactions&chain=${chain.id}`, { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#content-in')).toContainText(`Řetězec transakcí #${chain.id}`);
    await expect(page.locator('#content-in')).toContainText('Uživatel');
    await expect(page.locator('#content-in')).toContainText('Nové přihlášení');
  } finally {
    await switchLanguage(page, 'en_US.utf8');
    await logout(page, fixtures.user.username);
  }
});

test('dashboard transaction updater uses localized concern labels', async ({ page }) => {
  await login(page, fixtures.user);
  try {
    await switchLanguage(page, 'cs_CZ.utf8');
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    const rows = page.locator('#transactions table tr:has(td)');
    await expect(rows.first()).toBeVisible();
    await page.locator('#transactions table').evaluate((table) => {
      const currentRows = Array.from(table.querySelectorAll('tr'))
        .filter((row) => row.querySelector('td'));
      currentRows.slice(1).forEach((row) => row.remove());

      const row = currentRows[0];
      row.setAttribute('data-transaction-chain-id', 'stale');
      row.setAttribute('data-transaction-chain-progress', '0');
      row.querySelector('td:nth-child(2)').textContent = 'stale concern';
      row.querySelector('td:nth-child(3)').textContent = 'stale action';
    });

    const localizedRow = page.locator('#transactions table tr:has(td)', {
      hasText: 'Nové přihlášení',
    }).first();
    await expect(localizedRow).toBeVisible({ timeout: 10000 });
    await expect(localizedRow).toContainText('Uživatel');
  } finally {
    await switchLanguage(page, 'en_US.utf8');
    await logout(page, fixtures.user.username);
  }
});
