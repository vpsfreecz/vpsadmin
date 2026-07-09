<?php

use PHPUnit\Framework\TestCase;

if (!class_exists('CsrfTokenInvalid')) {
    class CsrfTokenInvalid extends Exception {}
}

class NullStateFormTemplate
{
    public function perex($title, $message = '') {}

    public function perex_format_errors($title, $response) {}
}

class RejectingStateResource
{
    public function update($id, $params)
    {
        fail_if_reached('API update was reached without CSRF validation');
    }
}

class RejectingStateMount
{
    public function update($params)
    {
        fail_if_reached('Mount update was reached without CSRF validation');
    }
}

class RejectingStateMountCollection
{
    public object $create;

    public function __construct()
    {
        $this->create = new class {
            public function getParameters($type)
            {
                return new stdClass();
            }
        };
    }

    public function __invoke($id)
    {
        return new RejectingStateMount();
    }
}

class RejectingStateVps
{
    public RejectingStateMountCollection $mount;

    public function __construct()
    {
        $this->mount = new RejectingStateMountCollection();
    }
}

class RejectingStateApi
{
    public object $vps;

    public function __construct()
    {
        $this->vps = new class {
            public RejectingStateMountCollection $mount;

            public function __construct()
            {
                $this->mount = new RejectingStateMountCollection();
            }
        };
    }

    public function vps($id)
    {
        return new RejectingStateVps();
    }
}

final class CsrfStateFormsTest extends TestCase
{
    public function testLifetimeStateChangeRejectsMissingCsrfBeforeApiUpdate(): void
    {
        $this->installStubs();

        global $xtpl, $api;

        $xtpl = new NullStateFormTemplate();
        $api = ['vps' => new RejectingStateResource()];
        $_GET = [
            'action' => 'set_state',
            'resource' => 'vps',
            'id' => '4242',
            'return' => 'https://attacker.invalid/after-state-change',
        ];
        $_POST = [
            'object_state' => 'hard_delete',
            'expiration_date' => '',
            'change_reason' => 'csrf proof',
        ];

        $this->expectException(CsrfTokenInvalid::class);

        require dirname(__DIR__, 2) . '/pages/page_lifetimes.php';
    }

    public function testReminderChangeRejectsMissingCsrfBeforeApiUpdate(): void
    {
        $this->installStubs();

        global $xtpl, $api;

        $xtpl = new NullStateFormTemplate();
        $api = ['vps' => new RejectingStateResource()];
        $_GET = [
            'action' => 'set',
            'resource' => 'vps',
            'id' => '4242',
        ];
        $_POST = [
            'remind_in' => 'date',
            'remind_after_date' => '2030-01-02',
        ];

        $this->expectException(CsrfTokenInvalid::class);

        require dirname(__DIR__, 2) . '/pages/page_reminder.php';
    }

    public function testMountEditRejectsMissingCsrfBeforeApiUpdate(): void
    {
        $this->installStubs();

        global $xtpl, $api;

        $xtpl = new NullStateFormTemplate();
        $api = new RejectingStateApi();
        $_GET = [
            'action' => 'mount_edit',
            'vps' => '101',
            'id' => '202',
        ];
        $_POST = [
            'on_start_fail' => 'fail_start',
            'return' => 'https://attacker.invalid/after-mount-edit',
        ];

        $this->expectException(CsrfTokenInvalid::class);

        require dirname(__DIR__, 2) . '/pages/page_dataset.php';
    }

    private function installStubs(): void
    {
        function csrf_check($name = 'common', $t = null)
        {
            throw new CsrfTokenInvalid();
        }

        function isLoggedIn()
        {
            return true;
        }

        function isAdmin()
        {
            return true;
        }

        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        function notify_user(...$args)
        {
            throw new RuntimeException('notify_user() should not be reached');
        }

        function redirect($url)
        {
            throw new RuntimeException('redirect() should not be reached');
        }

        function fail_if_reached($message)
        {
            throw new RuntimeException($message);
        }
    }
}
