const { expect } = require('@playwright/test');

const {
  gotoVpsDetail,
  waitForVpsStatus,
  waitForVpsTransactionsSettled,
} = require('./webui.cjs');

const CONSOLE_OPERATION_TIMEOUT = 10 * 60 * 1000;
const CONSOLE_LOGIN_TIMEOUT = 3 * 60 * 1000;

async function openConsole(page, vpsId) {
  await gotoVpsDetail(page, vpsId);
  await page.locator(`a[href*="page=console"][href*="veid=${vpsId}"]`, {
    hasText: 'Remote console',
  }).first().click();
  await expect(page).toHaveURL(new RegExp(`page=console.*veid=${vpsId}`));
  await expect(page.locator('#perex')).toContainText(/Remote Console for VPS|No console server available/);
}

async function expectConsoleIframe(page, vpsId) {
  await openConsole(page, vpsId);

  const iframe = page.locator('#vpsadmin-console-frame');
  if ((await iframe.count()) === 0) {
    await expect(page.locator('#perex')).toContainText('No console server available');
    return false;
  }

  await expect(iframe).toBeVisible();

  const src = await iframe.getAttribute('src');
  expect(src).toBeTruthy();

  const url = new URL(src);
  expect(url.pathname).toBe(`/console/${vpsId}`);
  expect(url.searchParams.get('session')).toMatch(/[A-Za-z0-9_-]+/);
  expect(url.searchParams.get('auth_type')).toBeNull();
  expect(url.searchParams.get('auth_token')).toBeNull();

  return true;
}

async function waitForConsoleFrame(page, vpsId, options = {}) {
  const timeout = options.timeout || 30 * 1000;
  const deadline = Date.now() + timeout;

  while (Date.now() < deadline) {
    const frame = page.frames().find((candidate) => {
      try {
        return new URL(candidate.url()).pathname === `/console/${vpsId}`;
      } catch (error) {
        return false;
      }
    });

    if (frame) {
      await frame.waitForFunction(() => window.remoteConsole && window.remoteConsole.term);
      return frame;
    }

    await page.waitForTimeout(250);
  }

  throw new Error(`Timed out waiting for console frame for VPS ${vpsId}`);
}

async function consoleText(frame) {
  return frame.evaluate(() => {
    const buffer = window.remoteConsole.term.buffer.active;
    const lines = [];

    for (let i = 0; i < buffer.length; i += 1) {
      const line = buffer.getLine(i);

      if (line) {
        lines.push(line.translateToString(true));
      }
    }

    return lines.join('\n');
  });
}

async function sendConsoleInput(frame, keys) {
  await frame.evaluate((input) => {
    window.remoteConsole.pendingData += input;
  }, keys);
}

async function waitForConsoleText(frame, pattern, name, options = {}) {
  const timeout = options.timeout || CONSOLE_LOGIN_TIMEOUT;
  const from = options.from || 0;
  const intervals = options.intervals || [1000, 2000, 5000];
  const deadline = Date.now() + timeout;
  let i = 0;
  let lastText = '';

  while (Date.now() < deadline) {
    lastText = await consoleText(frame);

    if (consoleTextMatches(lastText, pattern, from)) {
      return lastText;
    }

    await frame.page().waitForTimeout(intervals[Math.min(i, intervals.length - 1)]);
    i += 1;
  }

  throw new Error(`Timed out waiting for ${name}:\n${lastText}`);
}

function consoleTextMatches(text, pattern, from = 0) {
  const slice = text.slice(from);

  return pattern instanceof RegExp ? pattern.test(slice) : slice.includes(pattern);
}

function hasLoginPrompt(text) {
  return /login:\s*(?:\n\s*)*$/i.test(text);
}

async function expectConsoleRootLogin(page, vpsId, password) {
  await openConsole(page, vpsId);

  const frame = await waitForConsoleFrame(page, vpsId);
  let text = await consoleText(frame);

  if (!hasLoginPrompt(text)) {
    const loginPromptStart = text.length;
    await sendConsoleInput(frame, '\n');
    text = await waitForConsoleText(frame, /login:\s*/i, `console login prompt for VPS ${vpsId}`, {
      from: loginPromptStart,
    });
  }

  await sendConsoleInput(frame, 'root\n');
  text = await waitForConsoleText(frame, /password:\s*/i, `console password prompt for VPS ${vpsId}`);

  await sendConsoleInput(frame, `${password}\n`);
  text = await waitForConsoleText(frame, /root@.*[#]/m, `console shell prompt for VPS ${vpsId}`);

  await sendConsoleInput(frame, 'printf \'%s\\n\' "$((40 + 2))"\n');
  await waitForConsoleText(frame, /(?:^|[\r\n])42[\r\n]/, `console command output for VPS ${vpsId}`);
}

async function runConsoleVpsAction(page, vpsId, command, label, expectedStatus) {
  await openConsole(page, vpsId);

  const status = page.locator('#vps-action-status');
  await page.locator(`#aside a[href*="vps_do('${command}')"]`).click();

  await expect(status).toContainText(new RegExp(`^${escapeRegExp(label)} (planned|done|\\.\\.\\.)$`));
  await expect(status).toContainText(new RegExp(`^${escapeRegExp(label)} done$`), {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  await waitForVpsTransactionsSettled(page, vpsId);

  if (expectedStatus) {
    await waitForVpsStatus(page, vpsId, expectedStatus);
  }
}

async function generateConsoleRootPassword(page, vpsId) {
  await openConsole(page, vpsId);

  const password = page.locator('#root-password');
  await expect(password).toContainText('will be generated');
  await page.locator('#aside button', { hasText: 'Generate password' }).click();
  await expect(password).toContainText('configuring password...');
  await expect(password).toContainText(/^[a-zA-Z2-9]{8}$/, {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  const generatedPassword = (await password.innerText()).trim();
  await waitForVpsTransactionsSettled(page, vpsId);

  return generatedPassword;
}

async function bootConsoleRescue(page, vpsId, osTemplateId) {
  await openConsole(page, vpsId);

  await page.locator('#aside select[name="os_template"]').selectOption(String(osTemplateId));
  await page.locator('#aside input[name="root_mountpoint"]').fill('/mnt/webui-rescue');
  await page.locator('#boot-button').click();
  await expect(page.locator('#boot-button')).toContainText('Booting...');
  await expect(page.locator('#boot-button')).toContainText('Boot', {
    timeout: CONSOLE_OPERATION_TIMEOUT,
  });
  await waitForVpsTransactionsSettled(page, vpsId);
  await waitForVpsStatus(page, vpsId, 'running');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  bootConsoleRescue,
  expectConsoleRootLogin,
  expectConsoleIframe,
  generateConsoleRootPassword,
  openConsole,
  runConsoleVpsAction,
};
