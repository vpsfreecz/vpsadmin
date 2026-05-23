<?php

// Regression tests for POST handlers whose forms already render CSRF tokens.
// Each case must reject before forwarding attacker-controlled input to the API.

if ($argc === 1) {
    foreach (['lifetime', 'reminder', 'mount_edit'] as $case) {
        $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__FILE__) . ' ' . escapeshellarg($case);
        passthru($cmd, $status);

        if ($status !== 0) {
            exit($status);
        }
    }

    echo "CSRF-less state form submissions are rejected before API updates.\n";
    exit(0);
}

class CsrfTokenInvalid extends Exception {};

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

class NullTemplate
{
    public function perex($title, $message = '') {}
    public function perex_format_errors($title, $response) {}
}

class RejectingResource
{
    public function update($id, $params)
    {
        fail_if_reached('API update was reached without CSRF validation');
    }
}

class RejectingMount
{
    public function update($params)
    {
        fail_if_reached('Mount update was reached without CSRF validation');
    }
}

class RejectingMountCollection
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
        return new RejectingMount();
    }
}

class RejectingVps
{
    public RejectingMountCollection $mount;

    public function __construct()
    {
        $this->mount = new RejectingMountCollection();
    }
}

class RejectingApi
{
    public object $vps;

    public function __construct()
    {
        $this->vps = new class {
            public RejectingMountCollection $mount;

            public function __construct()
            {
                $this->mount = new RejectingMountCollection();
            }
        };
    }

    public function vps($id)
    {
        return new RejectingVps();
    }
}

$xtpl = new NullTemplate();
$case = $argv[1];

try {
    switch ($case) {
        case 'lifetime':
            $api = ['vps' => new RejectingResource()];
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
            require __DIR__ . '/../../../webui/pages/page_lifetimes.php';
            break;

        case 'reminder':
            $api = ['vps' => new RejectingResource()];
            $_GET = [
                'action' => 'set',
                'resource' => 'vps',
                'id' => '4242',
            ];
            $_POST = [
                'remind_in' => 'date',
                'remind_after_date' => '2030-01-02',
            ];
            require __DIR__ . '/../../../webui/pages/page_reminder.php';
            break;

        case 'mount_edit':
            $api = new RejectingApi();
            $_GET = [
                'action' => 'mount_edit',
                'vps' => '101',
                'id' => '202',
            ];
            $_POST = [
                'on_start_fail' => 'fail_start',
                'return' => 'https://attacker.invalid/after-mount-edit',
            ];
            require __DIR__ . '/../../../webui/pages/page_dataset.php';
            break;

        default:
            fwrite(STDERR, "Unknown case: $case\n");
            exit(1);
    }
} catch (CsrfTokenInvalid $e) {
    exit(0);
}

fwrite(STDERR, "Case $case did not reject a CSRF-less request.\n");
exit(1);
