<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunTestsInSeparateProcesses;
use PHPUnit\Framework\TestCase;

if (!class_exists('CsrfTokenInvalid')) {
    class CsrfTokenInvalid extends Exception {}
}

if (!defined('OAUTH2_CLIENT_ID')) {
    define('OAUTH2_CLIENT_ID', 'test-client-id');
}

if (!defined('OAUTH2_CLIENT_SECRET')) {
    define('OAUTH2_CLIENT_SECRET', 'test-client-secret');
}

class CapturingLogoutTemplate
{
    public string $lastTitle = '';
    public string $lastMessage = '';

    public function perex($title, $message = '')
    {
        $this->lastTitle = $title;
        $this->lastMessage = $message;
    }
}

class ExplodingLogoutApi
{
    public function logout()
    {
        throw new RuntimeException('API logout should not be reached');
    }

    public function getAuthenticationProvider()
    {
        throw new RuntimeException('OAuth2 token revocation should not be reached');
    }
}

class SuccessfulOAuthLogoutApi
{
    public SuccessfulOAuthLogoutProvider $provider;

    public function __construct()
    {
        $this->provider = new SuccessfulOAuthLogoutProvider();
    }

    public function getAuthenticationProvider()
    {
        return $this->provider;
    }
}

class SuccessfulOAuthLogoutProvider
{
    public bool $revoked = false;

    public function revokeAccessToken($params = [])
    {
        $this->revoked = true;
    }
}

class CapturedLogoutRedirect extends Exception
{
    public function __construct(public string $url)
    {
        parent::__construct($url);
    }
}

if (!function_exists('_')) {
    function _($s)
    {
        return $s;
    }
}

if (!function_exists('isLoggedIn')) {
    function isLoggedIn()
    {
        return $_SESSION["logged_in"] ?? false;
    }
}

if (!function_exists('csrf_check')) {
    function csrf_check($name = 'common', $t = null)
    {
        global $logoutExpiredSessionCsrfCalled, $logoutExpiredSessionCsrfValid;

        $logoutExpiredSessionCsrfCalled = true;

        if (!$logoutExpiredSessionCsrfValid) {
            throw new CsrfTokenInvalid();
        }
    }
}

if (!function_exists('redirect')) {
    function redirect($url)
    {
        throw new CapturedLogoutRedirect($url);
    }
}

require_once dirname(__DIR__, 2) . '/lib/login.lib.php';

#[RunTestsInSeparateProcesses]
#[PreserveGlobalState(false)]
final class LogoutExpiredSessionTest extends TestCase
{
    protected function setUp(): void
    {
        global $logoutExpiredSessionLoggedIn, $logoutExpiredSessionCsrfCalled,
        $logoutExpiredSessionCsrfValid, $xtpl, $api;

        $this->startSession();

        $logoutExpiredSessionLoggedIn = false;
        $logoutExpiredSessionCsrfCalled = false;
        $logoutExpiredSessionCsrfValid = false;
        $xtpl = new CapturingLogoutTemplate();
        $api = new ExplodingLogoutApi();
        $_GET = [];
        $_POST = [];
        $_SESSION = [];
    }

    protected function tearDown(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }

        $_SESSION = [];
    }

    public function testExpiredLogoutRequestDoesNotRequireCsrf(): void
    {
        global $logoutExpiredSessionCsrfCalled, $xtpl;

        $_SESSION = ['logged_in' => false];

        logoutUser();

        self::assertFalse($logoutExpiredSessionCsrfCalled);
        self::assertSame('Session expired', $xtpl->lastTitle);
        self::assertFalse($_SESSION['logged_in']);
    }

    public function testLoggedInLogoutStillRequiresCsrf(): void
    {
        global $logoutExpiredSessionLoggedIn, $logoutExpiredSessionCsrfCalled;

        $logoutExpiredSessionLoggedIn = true;
        $_SESSION = [
            'logged_in' => true,
            'auth_type' => 'oauth2',
        ];

        $this->expectException(CsrfTokenInvalid::class);

        try {
            logoutUser();
        } finally {
            self::assertTrue($logoutExpiredSessionCsrfCalled);
        }
    }

    public function testAutomatedLogoutShowsSessionExpiredMessage(): void
    {
        global $logoutExpiredSessionLoggedIn, $logoutExpiredSessionCsrfCalled,
        $logoutExpiredSessionCsrfValid, $xtpl, $api;

        $logoutExpiredSessionLoggedIn = true;
        $logoutExpiredSessionCsrfValid = true;
        $api = new SuccessfulOAuthLogoutApi();
        $_GET = ['timeout' => '1'];
        $_SESSION = [
            'logged_in' => true,
            'auth_type' => 'oauth2',
        ];

        logoutUser();

        self::assertTrue($logoutExpiredSessionCsrfCalled);
        self::assertTrue($api->provider->revoked);
        self::assertSame('Session expired', $xtpl->lastTitle);
    }

    public function testIntentionalLogoutKeepsGoodbyeMessage(): void
    {
        global $logoutExpiredSessionLoggedIn, $logoutExpiredSessionCsrfValid, $xtpl, $api;

        $logoutExpiredSessionLoggedIn = true;
        $logoutExpiredSessionCsrfValid = true;
        $api = new SuccessfulOAuthLogoutApi();
        $_GET = [];
        $_SESSION = [
            'logged_in' => true,
            'auth_type' => 'oauth2',
        ];

        logoutUser();

        self::assertTrue($api->provider->revoked);
        self::assertSame('Goodbye', $xtpl->lastTitle);
        self::assertSame('Logout successful', $xtpl->lastMessage);
    }

    public function testExpiredSwitchUserRequestRedirectsToLoginWithoutCsrf(): void
    {
        global $logoutExpiredSessionCsrfCalled;

        $_GET = ['user' => 'member@example.test'];
        $_SESSION = ['logged_in' => false];

        try {
            logoutAndSwitchUser();
        } catch (CapturedLogoutRedirect $e) {
            self::assertSame(
                '?page=login&action=login&user=member%40example.test',
                $e->url
            );
            self::assertFalse($logoutExpiredSessionCsrfCalled);
            return;
        }

        self::fail('Expected redirect to login');
    }

    private function startSession(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }

        session_id('logoutexpired' . bin2hex(random_bytes(8)));
        session_start();
    }
}
