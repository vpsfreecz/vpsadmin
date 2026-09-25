<?php

use PHPUnit\Framework\TestCase;

class StorageFreezeTestTemplate
{
    public string $lastTitle = '';
    public string $lastMessage = '';
    public array $cells = [];

    public function title($title) {}

    public function perex($title, $message = '')
    {
        $this->lastTitle = $title;
        $this->lastMessage = $message;
    }

    public function sbar_add($title, $url) {}

    public function sbar_out($title) {}

    public function title2($title) {}

    public function table_title($title) {}

    public function table_td($value)
    {
        $this->cells[] = $value;
    }

    public function table_tr() {}

    public function table_out() {}

    public function assign($name, $value) {}
}

class StorageFreezeTestResource
{
    public int $calls = 0;

    public function show()
    {
        $this->calls++;
        throw new RuntimeException('freeze API reached');
    }

    public function read_only($params)
    {
        $this->calls++;
        throw new RuntimeException('freeze API reached');
    }
}

class StorageFreezeTestApi
{
    public ?StorageFreezeTestResource $storage_freeze = null;
    public int $refreshes = 0;

    public function setup($force)
    {
        $this->refreshes++;
        $this->storage_freeze = new StorageFreezeTestResource();
    }
}

final class StorageFreezeUiTest extends TestCase
{
    public function testExistingSessionDiscoversNewApiResource(): void
    {
        $this->installStubs();

        global $api;
        $api = new StorageFreezeTestApi();
        $_SESSION = ['is_admin' => true, 'is_superadmin' => true];

        self::assertTrue(storage_freeze_resource_available());
        self::assertSame(1, $api->refreshes);
        self::assertTrue(storage_freeze_resource_available());
        self::assertSame(1, $api->refreshes);
    }

    public function testSupportUserCannotOpenFreezePage(): void
    {
        $this->installStubs();

        global $xtpl, $api;
        $xtpl = new StorageFreezeTestTemplate();
        $resource = new StorageFreezeTestResource();
        $api = (object) ['storage_freeze' => $resource];
        $_SESSION = ['is_admin' => true, 'is_superadmin' => false];
        $_GET = ['action' => 'storage_freeze'];

        require dirname(__DIR__, 2) . '/pages/page_cluster.php';

        self::assertSame(0, $resource->calls);
        self::assertSame('Storage freeze unavailable', $xtpl->lastTitle);
    }

    public function testContextSwitchedAdminCannotSubmitModeChange(): void
    {
        $this->installStubs();

        global $xtpl, $api;
        $xtpl = new StorageFreezeTestTemplate();
        $resource = new StorageFreezeTestResource();
        $api = (object) ['storage_freeze' => $resource];
        $_SESSION = ['is_admin' => true, 'is_superadmin' => true, 'context_switch' => true];
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_GET = ['action' => 'storage_freeze_change'];
        $_POST = ['mode' => 'read_only', 'reason' => 'test', 'expected_epoch' => '0'];

        require dirname(__DIR__, 2) . '/pages/page_cluster.php';

        self::assertSame(0, $resource->calls);
        self::assertSame('Storage freeze unavailable', $xtpl->lastTitle);
    }

    public function testModeChangeChecksCsrfBeforeCallingApi(): void
    {
        $this->installStubs();

        global $xtpl, $api, $storageFreezeCsrfChecked;
        $storageFreezeCsrfChecked = false;
        $xtpl = new StorageFreezeTestTemplate();
        $resource = new StorageFreezeTestResource();
        $api = (object) ['storage_freeze' => $resource];
        $_SESSION = ['is_admin' => true, 'is_superadmin' => true];
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_GET = ['action' => 'storage_freeze_change'];
        $_POST = ['mode' => 'read_only', 'reason' => 'test', 'expected_epoch' => '0'];

        try {
            require dirname(__DIR__, 2) . '/pages/page_cluster.php';
            self::fail('CSRF check did not run');
        } catch (RuntimeException $e) {
            self::assertSame('CSRF check', $e->getMessage());
            self::assertTrue($storageFreezeCsrfChecked);
            self::assertSame(0, $resource->calls);
        }
    }

    public function testStatusShowsCappedDatabaseBlockersAndEscapesAuditReason(): void
    {
        $this->installStubs();

        global $xtpl;
        $xtpl = new StorageFreezeTestTemplate();
        storage_freeze_status_page([
            'mode' => 'read_only', 'epoch' => 7, 'stable_epoch' => true,
            'db_drained' => false, 'repair_ready' => false,
            'reason' => '<script>unsafe</script>',
            'transition' => ['actor_user_login' => 'admin', 'actor_user_id' => 7],
            'counts' => ['prepared_intents' => 1000],
            'count_capped' => ['prepared_intents'],
            'sample_intent_ids' => [41, 42],
        ]);

        self::assertStringContainsString('does not prove', $xtpl->lastMessage);
        self::assertContains('1000+', $xtpl->cells);
        self::assertContains('41, 42', $xtpl->cells);
        self::assertContains('&lt;script&gt;unsafe&lt;/script&gt;', $xtpl->cells);
        self::assertContains('admin (#7)', $xtpl->cells);
        self::assertNotContains('<script>unsafe</script>', $xtpl->cells);
    }

    private function installStubs(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        if (!function_exists('h')) {
            function h($value)
            {
                return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
            }
        }

        function isAdmin()
        {
            return true;
        }

        function csrf_check()
        {
            global $storageFreezeCsrfChecked;
            $storageFreezeCsrfChecked = true;
            throw new RuntimeException('CSRF check');
        }

        require_once dirname(__DIR__, 2) . '/forms/cluster.forms.php';
    }
}
