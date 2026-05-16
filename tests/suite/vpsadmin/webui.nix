import ../../make-test.nix (
  {
    pkgs,
    ...
  }:
  let
    playwrightBrowsers = pkgs.playwright-driver.browsers-chromium;
    playwrightNodeModules = pkgs.runCommand "vpsadmin-webui-playwright-node-modules" { } ''
      mkdir -p "$out/lib"
      cp -R ${pkgs.playwright-test}/lib/node_modules "$out/lib/node_modules"
    '';
    playwrightRunner = pkgs.writeShellScriptBin "vpsadmin-webui-playwright" ''
      export NODE_PATH=${playwrightNodeModules}/lib/node_modules''${NODE_PATH:+:$NODE_PATH}
      export PLAYWRIGHT_BROWSERS_PATH="''${PLAYWRIGHT_BROWSERS_PATH:-${playwrightBrowsers}}"
      exec ${pkgs.nodejs}/bin/node ${playwrightNodeModules}/lib/node_modules/@playwright/test/cli.js "$@"
    '';

    playwrightConfig = pkgs.writeText "vpsadmin-webui-playwright.config.cjs" ''
      const fs = require('fs');
      const path = require('path');

      const browsersPath = '${playwrightBrowsers}';
      const chromiumDir = fs.readdirSync(browsersPath).find((name) => name.startsWith('chromium-'));
      const chromiumExecutable = path.join(browsersPath, chromiumDir, 'chrome-linux', 'chrome');

      module.exports = {
        timeout: 60000,
        expect: {
          timeout: 10000,
        },
        fullyParallel: false,
        workers: 1,
        reporter: [['line']],
        use: {
          actionTimeout: 15000,
          baseURL: 'http://webui.vpsadmin.test',
          headless: true,
          navigationTimeout: 30000,
          screenshot: 'only-on-failure',
          trace: 'off',
          video: 'off',
        },
        projects: [
          {
            name: 'chromium',
            use: {
              browserName: 'chromium',
              launchOptions: {
                executablePath: chromiumExecutable,
                args: ['--no-sandbox'],
              },
            },
          },
        ],
      };
    '';

    playwrightSpec = pkgs.writeText "vpsadmin-webui.spec.cjs" ''
      const { test, expect } = require('${playwrightNodeModules}/lib/node_modules/@playwright/test');

      const username = 'test-admin';
      const password = 'testAdminPassword';

      const loginButton = (page) =>
        page.locator('form[action="?page=login&action=login"] input[type="submit"]');

      const logoutButton = (page) =>
        page.locator('form[action="?page=login&action=logout"] input[type="submit"]');

      async function openWebuiLogin(page) {
        await page.goto('/', { waitUntil: 'domcontentloaded' });
        await expect(loginButton(page)).toHaveValue('Log in');
        await loginButton(page).click();
        await expect(page).toHaveURL(/api\.vpsadmin\.test/);
        await expect(page.locator('input[name="user"]')).toBeVisible();
      }

      async function submitCredentials(page, userPassword) {
        await page.locator('input[name="user"]').fill(username);
        await page.locator('input[name="password"]').fill(userPassword);
        await page.locator('input[name="login_credentials"]').click();
      }

      test('anonymous webui loads', async ({ page }) => {
        await page.goto('/', { waitUntil: 'domcontentloaded' });
        await expect(page).toHaveTitle(/vpsAdmin/);
        await expect(loginButton(page)).toHaveValue('Log in');
      });

      test('invalid OAuth password stays on auth form', async ({ page }) => {
        await openWebuiLogin(page);
        await submitCredentials(page, 'wrong-password');

        await expect(page.locator('.alert-danger')).toContainText('invalid user or password');
        await expect(page.locator('input[name="user"]')).toHaveValue(username);
        await expect(page).toHaveURL(/api\.vpsadmin\.test/);
      });

      test('OAuth login and logout work', async ({ page }) => {
        await openWebuiLogin(page);
        await submitCredentials(page, password);

        await expect(logoutButton(page)).toHaveValue(/Logout \(test-admin\)/);
        await expect(page.locator('#nav a[href="?page=cluster"]')).toBeVisible();

        await logoutButton(page).click();
        await expect(loginButton(page)).toHaveValue('Log in');
        await expect(page.locator('#perex h1')).toContainText('Goodbye');
      });
    '';
  in
  {
    name = "vpsadmin-webui";

    description = ''
      Boot the vpsAdmin services VM and exercise the PHP web UI through
      Playwright.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "webui"
    ];

    machines = {
      services = {
        spin = "nixos";
        tags = [ "vpsadmin-services" ];
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../configs/nixos/vpsadmin-services.nix
          ];

          environment.systemPackages = [
            playwrightRunner
          ];

          system.extraDependencies = [
            playwrightBrowsers
            playwrightConfig
            playwrightSpec
          ];
        };
      };
    };

    testScript = ''
      def wait_for_webui
        wait_until_block_succeeds(name: 'webui responds') do
          _, output = services.succeeds('curl --silent --fail-with-body http://webui.vpsadmin.test/')
          expect(output).to include('vpsAdmin')
          expect(output).not_to include('Unable to connect to the API server')
          true
        end
      end

      def run_playwright
        services.succeeds(<<~'SH', timeout: 180)
          set -euo pipefail

          export CI=1
          export HOME=/tmp/vpsadmin-webui-playwright-home
          export PLAYWRIGHT_BROWSERS_PATH=${playwrightBrowsers}

          rm -rf "$HOME" /tmp/vpsadmin-webui-playwright-results
          mkdir -p "$HOME"

          ${playwrightRunner}/bin/vpsadmin-webui-playwright test ${playwrightSpec} \
            --config=${playwrightConfig} \
            --output=/tmp/vpsadmin-webui-playwright-results
        SH
      end

      before(:suite) do
        services.start
        services.wait_for_vpsadmin_api
        wait_for_webui
      end

      describe 'webui browser flow' do
        it 'passes Playwright smoke tests' do
          run_playwright
        end
      end
    '';
  }
)
