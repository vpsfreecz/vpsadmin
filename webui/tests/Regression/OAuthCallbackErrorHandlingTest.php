<?php

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunTestsInSeparateProcesses;
use PHPUnit\Framework\TestCase;

#[RunTestsInSeparateProcesses]
#[PreserveGlobalState(false)]
final class OAuthCallbackErrorHandlingTest extends TestCase
{
    private const DIAGNOSTIC = 'vpsAdmin OAuth callback failed';
    private const SENTINEL = 'oauth-sensitive-sentinel';
    private const GENERIC_MESSAGE = 'vpsAdmin was unable to obtain access token from the authorization server, please contact support if the error persists.';

    public static function callbackFailures(): array
    {
        return [
            'setup Exception' => ['setup_exception', ['setup', 'perex', 'page_returned']],
            'provider lookup Exception' => ['lookup_exception', ['setup', 'provider', 'perex', 'page_returned']],
            'provider Exception' => ['provider_exception', ['setup', 'provider', 'token', 'perex', 'page_returned']],
            'provider TypeError' => ['provider_type_error', ['setup', 'provider', 'token', 'perex', 'page_returned']],
            'provider Error' => ['provider_error', ['setup', 'provider', 'token', 'perex', 'page_returned']],
            'loginUser Exception' => ['login_exception', ['setup', 'provider', 'token', 'login', 'perex', 'page_returned']],
        ];
    }

    #[DataProvider('callbackFailures')]
    public function testCallbackFailuresHaveOneSafeNativeDiagnostic(string $case, array $events): void
    {
        $result = $this->runPage($case);

        self::assertSame(0, $result['exit']);
        self::assertSame('', $result['stderr']);
        $response = json_decode($result['stdout'], true, flags: JSON_THROW_ON_ERROR);
        self::assertSame($events, $response['events']);
        self::assertSame([['Authentication error', self::GENERIC_MESSAGE]], $response['messages']);
        self::assertSame('1', $response['log_errors']);

        $lines = preg_split('/\R/', trim($result['log']));
        self::assertCount(1, $lines);
        self::assertSame(self::DIAGNOSTIC, preg_replace('/^\[[^\]]+\]\s*/', '', $lines[0]));

        foreach (['stdout', 'stderr', 'log'] as $sink) {
            self::assertStringNotContainsString(self::SENTINEL, $result[$sink], $sink);
        }
    }

    public function testSuccessKeepsCallOrderRawInputsAndRedirect(): void
    {
        $result = $this->runPage('success');

        self::assertSame(0, $result['exit']);
        self::assertSame('', $result['stderr']);
        self::assertSame('', $result['log']);
        $response = json_decode($result['stdout'], true, flags: JSON_THROW_ON_ERROR);
        self::assertSame(['setup', 'provider', 'token', 'login', 'redirect'], $response['events']);
        self::assertSame([], $response['messages']);
        self::assertSame('?page=cluster&filter=' . self::SENTINEL, $response['redirect']);
        self::assertSame([
            'action' => 'callback',
            'code' => 'code-' . self::SENTINEL,
            'state' => 'state-' . self::SENTINEL,
        ], $response['token_inputs']['get']);
        self::assertSame([
            'access_url' => $response['redirect'],
            'oauth2_state' => 'state-' . self::SENTINEL,
        ], $response['token_inputs']['session']);
        self::assertSame([
            'REQUEST_METHOD' => 'GET',
            'HTTP_COOKIE' => 'cookie-' . self::SENTINEL,
            'HTTP_AUTHORIZATION' => 'Bearer ' . self::SENTINEL,
            'HTTP_REFERER' => 'https://example.test/?code=' . self::SENTINEL,
        ], $response['token_inputs']['server']);
    }

    public function testNoCodeProviderErrorKeepsExistingResponseAndDoesNotLog(): void
    {
        $result = $this->runPage('no_code');

        self::assertSame(0, $result['exit']);
        self::assertSame('', $result['stderr']);
        self::assertSame('', $result['log']);
        $response = json_decode($result['stdout'], true, flags: JSON_THROW_ON_ERROR);
        self::assertSame(['perex', 'page_returned'], $response['events']);
        self::assertSame([[
            'Authentication error',
            'Authorization server reports: &lt;provider declined&gt;<br>'
                . 'Please try to sign in again or contact support if the error persists.',
        ]], $response['messages']);
    }

    public function testNonCallbackFailureStillHasOrdinaryNativeDiagnostics(): void
    {
        $result = $this->runPage('initiation_exception');

        self::assertSame(255, $result['exit']);
        self::assertSame('', $result['stdout']);
        self::assertStringContainsString(self::SENTINEL, $result['stderr']);
        self::assertStringContainsString(self::SENTINEL, $result['log']);
        self::assertStringNotContainsString(self::DIAGNOSTIC, $result['log']);
        self::assertStringNotContainsString(self::GENERIC_MESSAGE, $result['stderr']);
    }

    private function runPage(string $case): array
    {
        $script = tempnam(sys_get_temp_dir(), 'oauth-page-');
        $log = tempnam(sys_get_temp_dir(), 'oauth-log-');
        self::assertNotFalse($script);
        self::assertNotFalse($log);
        file_put_contents($script, <<<'PHP'
            <?php
            $case = $argv[2];
            $detail = 'oauth-sensitive-sentinel code state access_token refresh_token client_secret provider body';
            $events = [];
            $messages = [];
            $tokenInputs = [];
            $_GET = ['action' => 'callback', 'code' => 'code-oauth-sensitive-sentinel', 'state' => 'state-oauth-sensitive-sentinel'];
            $_SESSION = ['access_url' => '?page=cluster&filter=oauth-sensitive-sentinel', 'oauth2_state' => $_GET['state']];
            $_SERVER = [
                'REQUEST_METHOD' => 'GET',
                'HTTP_COOKIE' => 'cookie-oauth-sensitive-sentinel',
                'HTTP_AUTHORIZATION' => 'Bearer oauth-sensitive-sentinel',
                'HTTP_REFERER' => 'https://example.test/?code=oauth-sensitive-sentinel',
            ];

            if ($case === 'no_code') {
                $_GET = ['action' => 'callback', 'error_description' => '<provider declined>'];
            } elseif ($case === 'initiation_exception') {
                $_GET['action'] = 'login';
            }

            $xtpl = new class {
                public function perex($title, $message = '') {
                    global $events, $messages;
                    $events[] = 'perex';
                    $messages[] = [$title, $message];
                }
            };
            $api = new class {
                public function getAuthenticationProvider() {
                    global $case, $events, $detail;
                    $events[] = 'provider';
                    if ($case === 'lookup_exception') {
                        throw new Exception($detail);
                    }
                    return new class {
                        public function requestAccessToken() {
                            global $case, $events, $detail, $tokenInputs;
                            $events[] = 'token';
                            if ($case === 'provider_exception') {
                                throw new Exception($detail);
                            } elseif ($case === 'provider_type_error') {
                                throw new TypeError($detail);
                            } elseif ($case === 'provider_error') {
                                throw new Error($detail);
                            }
                            $tokenInputs = ['get' => $_GET, 'session' => $_SESSION, 'server' => $_SERVER];
                        }
                    };
                }
            };
            function setupOAuth2ForLogin() {
                global $case, $events, $detail;
                $events[] = 'setup';
                if ($case === 'setup_exception' || $case === 'initiation_exception') {
                    throw new Exception($detail);
                }
            }
            function loginUser($target) {
                global $case, $events, $detail;
                $events[] = 'login';
                if ($case === 'login_exception') {
                    throw new Exception($detail);
                }
                redirect($target);
            }
            function redirect($target) {
                global $events, $messages, $tokenInputs;
                $events[] = 'redirect';
                echo json_encode(['events' => $events, 'messages' => $messages, 'token_inputs' => $tokenInputs, 'redirect' => $target]);
                exit;
            }
            function isAdmin() { return false; }
            function h($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); }
            if (!function_exists('_')) {
                function _($value) { return $value; }
            }
            require $argv[1];
            $events[] = 'page_returned';
            echo json_encode(['events' => $events, 'messages' => $messages, 'log_errors' => ini_get('log_errors')]);
            PHP);

        try {
            $process = proc_open([
                PHP_BINARY,
                '-d', 'log_errors=1',
                '-d', 'display_errors=stderr',
                '-d', 'error_reporting=-1',
                '-d', 'error_log=' . $log,
                $script,
                dirname(__DIR__, 2) . '/pages/page_login.php',
                $case,
            ], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
            self::assertIsResource($process);
            fclose($pipes[0]);
            $stdout = stream_get_contents($pipes[1]);
            $stderr = stream_get_contents($pipes[2]);
            fclose($pipes[1]);
            fclose($pipes[2]);

            return ['exit' => proc_close($process), 'stdout' => $stdout, 'stderr' => $stderr, 'log' => file_get_contents($log)];
        } finally {
            unlink($script);
            unlink($log);
        }
    }
}
