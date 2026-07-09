<?php

use PHPUnit\Framework\TestCase;

if (!class_exists('CsrfTokenInvalid')) {
    class CsrfTokenInvalid extends Exception {}
}

class CapturingContextSwitchTemplate
{
    public string $lastTitle = '';
    public string $lastMessage = '';

    public function perex($title, $message = '')
    {
        $this->lastTitle = $title;
        $this->lastMessage = $message;
    }
}

final class CsrfContextSwitchTest extends TestCase
{
    public function testGetContextSwitchIsRejectedAsInvalidRequest(): void
    {
        $this->installStubs();

        global $csrfCalled, $switchCalled, $loggedIn, $admin, $xtpl, $api;

        $csrfCalled = false;
        $switchCalled = false;
        $loggedIn = true;
        $admin = true;
        $xtpl = new CapturingContextSwitchTemplate();
        $api = new stdClass();
        $_SESSION = ['context_switch' => false];
        $_SERVER['REQUEST_METHOD'] = 'GET';
        $_GET = [
            'action' => 'switch_context',
            'm_id' => '7331',
            'next' => '?page=cluster',
        ];
        $_POST = [];

        require dirname(__DIR__, 2) . '/pages/page_login.php';

        self::assertFalse($switchCalled);
        self::assertFalse($csrfCalled);
        self::assertSame('Invalid request', $xtpl->lastTitle);
    }

    public function testPostContextSwitchRequiresCsrfToken(): void
    {
        $this->installStubs();

        global $csrfCalled, $switchCalled, $loggedIn, $admin, $xtpl, $api;

        $csrfCalled = false;
        $switchCalled = false;
        $loggedIn = true;
        $admin = true;
        $xtpl = new CapturingContextSwitchTemplate();
        $api = new stdClass();
        $_SESSION = ['context_switch' => false];
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_GET = ['action' => 'switch_context'];
        $_POST = [
            'm_id' => '7331',
            'next' => '?page=cluster',
        ];

        $this->expectException(CsrfTokenInvalid::class);

        try {
            require dirname(__DIR__, 2) . '/pages/page_login.php';
        } finally {
            self::assertTrue($csrfCalled);
            self::assertFalse($switchCalled);
        }
    }

    public function testContextSwitchRendersPostFormWithCsrfToken(): void
    {
        $this->installStubs();

        global $loggedIn, $admin, $xtpl, $api;

        $loggedIn = false;
        $admin = true;
        $xtpl = new CapturingContextSwitchTemplate();
        $api = new stdClass();
        $_SESSION = ['context_switch' => false];
        $_GET = ['action' => 'list'];
        $_POST = [];

        require dirname(__DIR__, 2) . '/pages/page_adminm.php';

        $html = context_switch_form(7331, '?page=adminm&action=edit&id=7331', 'Switch context');

        self::assertStringContainsString('method="post"', $html);

        foreach (['csrf_token', 'm_id', 'next'] as $field) {
            self::assertStringContainsString('name="' . $field . '"', $html);
        }

        self::assertStringNotContainsString('<a href="?page=login&action=switch_context', $html);
    }

    private function installStubs(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        function h($v)
        {
            if (is_null($v)) {
                return '';
            }

            return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        }

        function csrf_token($name = 'common', $count = 1000)
        {
            return 'csrf-token-for-context-switch';
        }

        function csrf_check($name = 'common', $t = null)
        {
            global $csrfCalled;

            $csrfCalled = true;
            throw new CsrfTokenInvalid();
        }

        function isLoggedIn()
        {
            global $loggedIn;

            return $loggedIn;
        }

        function isAdmin()
        {
            global $admin;

            return $admin;
        }

        function switchUserContext($target_user_id)
        {
            global $switchCalled;

            $switchCalled = true;
            throw new RuntimeException('switchUserContext() should not be reached');
        }

        function setupOAuth2ForLogin() {}

        function logoutUser() {}

        function logoutAndSwitchUser() {}

        function regainAdminUser() {}
    }
}
