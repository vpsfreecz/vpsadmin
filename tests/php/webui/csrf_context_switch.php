<?php

// Regression tests for admin context switching. It must be POST-only,
// CSRF-protected, and rendered as a form rather than a GET link.

if ($argc === 1) {
    foreach (['get', 'post', 'render'] as $case) {
        $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__FILE__) . ' ' . escapeshellarg($case);
        passthru($cmd, $status);

        if ($status !== 0) {
            exit($status);
        }
    }

    echo "Admin context switch is POST-only and CSRF-protected.\n";
    exit(0);
}

class CsrfTokenInvalid extends Exception {};

$csrfCalled = false;
$switchCalled = false;
$loggedIn = true;
$admin = true;

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

class CapturingTemplate
{
    public string $lastTitle = '';
    public string $lastMessage = '';

    public function perex($title, $message = '')
    {
        $this->lastTitle = $title;
        $this->lastMessage = $message;
    }
}

$case = $argv[1];
$xtpl = new CapturingTemplate();
$api = new stdClass();
$_SESSION = ['context_switch' => false];

try {
    switch ($case) {
        case 'get':
            $_SERVER['REQUEST_METHOD'] = 'GET';
            $_GET = [
                'action' => 'switch_context',
                'm_id' => '7331',
                'next' => '?page=cluster',
            ];
            $_POST = [];

            require __DIR__ . '/../../../webui/pages/page_login.php';

            if ($switchCalled || $csrfCalled) {
                fwrite(STDERR, "GET context switch reached switch or CSRF handler.\n");
                exit(1);
            }

            if ($xtpl->lastTitle !== 'Invalid request') {
                fwrite(STDERR, "GET context switch was not rejected as invalid.\n");
                exit(1);
            }
            break;

        case 'post':
            $_SERVER['REQUEST_METHOD'] = 'POST';
            $_GET = ['action' => 'switch_context'];
            $_POST = [
                'm_id' => '7331',
                'next' => '?page=cluster',
            ];

            require __DIR__ . '/../../../webui/pages/page_login.php';
            fwrite(STDERR, "POST context switch without CSRF token was not rejected.\n");
            exit(1);

        case 'render':
            $loggedIn = false;
            $_GET = ['action' => 'list'];
            $_POST = [];

            require __DIR__ . '/../../../webui/pages/page_adminm.php';
            $html = context_switch_form(7331, '?page=adminm&action=edit&id=7331', 'Switch context');

            if (!str_contains($html, 'method="post"')) {
                fwrite(STDERR, "Context switch UI does not render a POST form.\n");
                exit(1);
            }

            foreach (['csrf_token', 'm_id', 'next'] as $field) {
                if (!str_contains($html, 'name="' . $field . '"')) {
                    fwrite(STDERR, "Context switch form is missing $field.\n");
                    exit(1);
                }
            }

            if (str_contains($html, '<a href="?page=login&action=switch_context')) {
                fwrite(STDERR, "Context switch UI still renders a GET link.\n");
                exit(1);
            }
            break;

        default:
            fwrite(STDERR, "Unknown case: $case\n");
            exit(1);
    }
} catch (CsrfTokenInvalid $e) {
    if ($case !== 'post' || $switchCalled) {
        fwrite(STDERR, "Unexpected CSRF rejection state for $case.\n");
        exit(1);
    }

    exit(0);
}
