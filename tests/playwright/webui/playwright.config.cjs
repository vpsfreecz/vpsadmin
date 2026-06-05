const fs = require('fs');
const path = require('path');

function chromiumExecutable() {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE) {
    return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  }

  const browsersPath = process.env.PLAYWRIGHT_BROWSERS_PATH;

  if (!browsersPath) {
    return undefined;
  }

  const chromiumDir = fs
    .readdirSync(browsersPath)
    .find((name) => name.startsWith('chromium-'));

  if (!chromiumDir) {
    return undefined;
  }

  const candidates = [
    path.join(browsersPath, chromiumDir, 'chrome-linux64', 'chrome'),
    path.join(browsersPath, chromiumDir, 'chrome-linux', 'chrome'),
  ];
  const executable = candidates.find((candidate) => fs.existsSync(candidate));

  if (!executable) {
    throw new Error(
      `Unable to find Chromium executable; checked: ${candidates.join(', ')}`,
    );
  }

  return executable;
}

module.exports = {
  timeout: 15 * 60 * 1000,
  expect: {
    timeout: 20 * 1000,
  },
  fullyParallel: false,
  workers: 1,
  reporter: [['line']],
  testDir: './specs',
  use: {
    actionTimeout: 15 * 1000,
    baseURL: process.env.WEBUI_BASE_URL || 'http://webui.vpsadmin.test',
    headless: true,
    navigationTimeout: 45 * 1000,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'off',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        browserName: 'chromium',
        launchOptions: {
          executablePath: chromiumExecutable(),
          args: ['--no-sandbox'],
        },
      },
    },
  ],
};
