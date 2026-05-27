const fs = require('fs');
const { execFileSync } = require('child_process');
const { expect } = require('@playwright/test');

const vpsadminctlConfigFile = '/etc/haveapi-client.yml';

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
      const value = ((await control.getAttribute('value')) || (await control.innerText())).trim();

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

async function waitForQueryParams(page, params, options = {}) {
  await page.waitForURL(
    (url) => Object.entries(params).every(
      ([name, value]) => url.searchParams.get(name) === String(value),
    ),
    {
      timeout: options.timeout || 20000,
    },
  );
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
        try {
          await gotoVpsDetail(page, vpsId);
          return detailValue(page, label);
        } catch (error) {
          return `Unable to read VPS detail ${label}: ${error.message}`;
        }
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
  const pendingStates = options.pendingStates || ['queued', 'rollbacking'];
  const failedStates = options.failedStates || ['failed', 'fatal'];

  await expect
    .poll(
      async () => {
        if (canPollTransactionsFromVpsadminctl(options)) {
          return readVpsTransactionStateFromVpsadminctl(vpsId, pendingStates, failedStates);
        }

        return readVpsTransactionStateFromPage(page, vpsId, pendingStates, failedStates);
      },
      {
        timeout,
        intervals: [1000, 2000, 5000],
      },
    )
    .toBe('settled');
}

function canPollTransactionsFromVpsadminctl(options = {}) {
  return options.transactionSource !== 'page'
    && process.env.VPSADMIN_WEBUI_TRANSACTION_SOURCE !== 'page'
    && fs.existsSync(vpsadminctlConfigFile);
}

function readVpsTransactionStateFromVpsadminctl(vpsId, pendingStates, failedStates) {
  try {
    const chains = listVpsTransactionChains(vpsId);

    return transactionStateFromChains(chains, pendingStates, failedStates, 'VPS');
  } catch (error) {
    if (error.transactionChainFailed) {
      throw error;
    }

    return `unable to read VPS transaction chains: ${error.message}`;
  }
}

async function readVpsTransactionStateFromPage(page, vpsId, pendingStates, failedStates) {
  try {
    await page.goto(`/?page=transactions&class_name=Vps&row_id=${vpsId}`, {
      waitUntil: 'domcontentloaded',
    });

    const rows = page.locator('tr', {
      has: page.locator('a[href*="page=transactions&chain="]'),
    });
    const texts = await rows.allInnerTexts();
    const failed = texts.find(
      (text) => failedStates.some((state) => stateTextMatches(text, state)),
    );

    if (failed) {
      throw transactionFailureError(`VPS transaction failed: ${failed}`);
    }

    return texts.some((text) => pendingStates.some((state) => stateTextMatches(text, state)))
      ? 'pending'
      : 'settled';
  } catch (error) {
    if (error.transactionChainFailed) {
      throw error;
    }

    return `unable to read VPS transaction page: ${error.message}`;
  }
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
        if (canPollTransactionsFromVpsadminctl(options)) {
          return readTransactionChainsStateFromVpsadminctl(
            chainIds,
            pendingStates,
            failedStates,
            options,
          );
        }

        return readTransactionChainsStateFromPage(
          page,
          chainIds,
          pendingStates,
          failedStates,
          options,
        );
      },
      {
        timeout,
        intervals: [1000, 2000, 5000],
      },
    )
    .toBe('settled');
}

function readTransactionChainsStateFromVpsadminctl(chainIds, pendingStates, failedStates, options) {
  try {
    const chains = showTransactionChains(chainIds);

    return transactionStateFromChains(
      chains,
      pendingStates.concat(['missing']),
      options.allowFailed ? [] : failedStates,
      'Transaction',
      chainIds,
    );
  } catch (error) {
    if (error.transactionChainFailed) {
      throw error;
    }

    return `unable to read transaction chains: ${error.message}`;
  }
}

async function readTransactionChainsStateFromPage(
  page,
  chainIds,
  pendingStates,
  failedStates,
  options,
) {
  try {
    const states = [];

    for (const chainId of chainIds) {
      await page.goto(`/?page=transactions&chain=${chainId}`, {
        waitUntil: 'domcontentloaded',
      });

      const state = (await detailValue(page, 'State')).toLowerCase();
      states.push(`${chainId}:${state}`);

      if (!options.allowFailed && failedStates.includes(state)) {
        throw transactionFailureError(`Transaction chain ${chainId} failed`);
      }
    }

    return states.some((entry) => pendingStates.some((state) => entry.endsWith(`:${state}`)))
      ? 'pending'
      : 'settled';
  } catch (error) {
    if (error.transactionChainFailed) {
      throw error;
    }

    return `unable to read transaction chain page: ${error.message}`;
  }
}

function transactionStateFromChains(chains, pendingStates, failedStates, label, chainIds = null) {
  const chainsById = new Map(chains.map((chain) => [String(chain.id), chain]));
  const selectedChains = chainIds
    ? chainIds.map((id) => chainsById.get(String(id)) || {
      id,
      name: 'missing',
      progress: 0,
      size: 0,
      state: 'missing',
    })
    : chains;
  const failed = selectedChains.find((chain) => failedStates.includes(chain.state));

  if (failed) {
    throw transactionFailureError(
      `${label} transaction chain ${formatTransactionChain(failed)} failed`,
    );
  }

  return selectedChains.some((chain) => pendingStates.includes(chain.state))
    ? 'pending'
    : 'settled';
}

function formatTransactionChain(chain) {
  return `#${chain.id} ${chain.name} state=${chain.state} progress=${chain.progress}/${chain.size}`;
}

function transactionFailureError(message) {
  const error = new Error(message);
  error.transactionChainFailed = true;
  return error;
}

function listVpsTransactionChains(vpsId) {
  const rowId = positiveInteger(vpsId, 'vpsId');
  const response = runVpsadminctl([
    'transaction_chain',
    'list',
    '--',
    '--class-name',
    'Vps',
    '--row-id',
    String(rowId),
  ]);

  return transactionChainListFromResponse(response).map(normalizeTransactionChain);
}

function showTransactionChains(chainIds) {
  return chainIds.map((chainId) => {
    const id = positiveInteger(chainId, 'chainId');
    const response = runVpsadminctl(['transaction_chain', 'show', String(id)]);

    return normalizeTransactionChain(transactionChainFromResponse(response));
  });
}

function runVpsadminctl(args) {
  const output = execFileSync(
    'vpsadminctl',
    ['--raw', ...args],
    {
      encoding: 'utf8',
      timeout: 30000,
    },
  );

  return parseJsonPrefix(output);
}

function transactionChainListFromResponse(response) {
  const payload = response.response || response;
  const chains = Array.isArray(payload) ? payload : payload.transaction_chains;

  if (!Array.isArray(chains)) {
    throw new Error(`vpsadminctl did not return transaction_chains: ${JSON.stringify(response)}`);
  }

  return chains;
}

function transactionChainFromResponse(response) {
  const payload = response.response || response;
  const chain = payload.transaction_chain;

  if (!chain) {
    throw new Error(`vpsadminctl did not return transaction_chain: ${JSON.stringify(response)}`);
  }

  return chain;
}

function normalizeTransactionChain(chain) {
  return {
    ...chain,
    state: String(chain.state),
  };
}

function parseJsonPrefix(text) {
  const start = text.search(/[\[{]/);

  if (start === -1) {
    throw new Error(`vpsadminctl did not return JSON: ${text}`);
  }

  const stack = [];
  let inString = false;
  let escaped = false;

  for (let i = start; i < text.length; i += 1) {
    const char = text[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }

      continue;
    }

    if (char === '"') {
      inString = true;
    } else if (char === '{') {
      stack.push('}');
    } else if (char === '[') {
      stack.push(']');
    } else if (char === '}' || char === ']') {
      if (stack.pop() !== char) {
        throw new Error(`vpsadminctl returned invalid JSON: ${text}`);
      }

      if (stack.length === 0) {
        return JSON.parse(text.slice(start, i + 1));
      }
    }
  }

  throw new Error(`vpsadminctl returned incomplete JSON: ${text}`);
}

function positiveInteger(value, name) {
  const number = Number(value);

  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${name} must be a positive integer, got ${value}`);
  }

  return number;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function stateTextMatches(text, state) {
  return new RegExp(`\\b${escapeRegExp(state)}\\b`).test(text);
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
  waitForQueryParams,
  waitForTransactionChainsSettled,
  waitForVpsTransactionsSettled,
  waitForVpsStatus,
  withAcceptedDialog,
};
