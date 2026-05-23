<?php

// Regression test for outage update reporter names rendered by
// webui/forms/outage.forms.php::outage_details().

if (!function_exists('_')) {
    function _($s)
    {
        return $s;
    }
}

function isAdmin()
{
    return true;
}
function isLoggedIn()
{
    return true;
}
function tolocaltz($value, $fmt = null)
{
    return (string) $value;
}
function h($v)
{
    if (is_null($v)) {
        return '';
    }

    return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
function boolean_icon($v)
{
    return $v ? 'yes' : 'no';
}

class FakeCollection implements IteratorAggregate, Countable
{
    private array $items;

    public function __construct(array $items = [])
    {
        $this->items = $items;
    }
    public function getIterator(): Traversable
    {
        return new ArrayIterator($this->items);
    }
    public function count(): int
    {
        return count($this->items);
    }
    public function asArray(): array
    {
        return $this->items;
    }
}

class FakeRelation
{
    private FakeCollection $collection;

    public function __construct(array $items = [])
    {
        $this->collection = new FakeCollection($items);
    }

    public function list($params = [])
    {
        return $this->collection;
    }
}

class FakeOutage
{
    public int $id = 31337;
    public string $state = 'announced';
    public string $begins_at = '2026-05-21 10:00:00 UTC';
    public int $duration = 10;
    public string $type = 'maintenance';
    public string $impact = 'network';
    public bool $auto_resolve = false;
    public int $affected_user_count = 0;
    public int $affected_direct_vps_count = 0;
    public int $affected_indirect_vps_count = 0;
    public int $affected_export_count = 0;
    public FakeRelation $entity;
    public FakeRelation $handler;
    public string $en_summary = 'escaped summary';
    public string $en_description = 'escaped description';

    public function __construct()
    {
        $this->entity = new FakeRelation([(object) ['label' => 'vpsAdmin']]);
        $this->handler = new FakeRelation([]);
    }
}

class FakeXtpl
{
    public array $cells = [];

    public function sbar_add($label, $url) {}
    public function title($title) {}
    public function table_title($title) {}
    public function table_add_category($title) {}
    public function table_td($content, ...$args)
    {
        $this->cells[] = (string) $content;
    }
    public function table_tr() {}
    public function table_out() {}
}

$payload = '<img src=x onerror=alert("outage-reporter-xss")>';

$xtpl = new FakeXtpl();
$api = (object) [
    'outage' => new class {
        public function show($id)
        {
            return new FakeOutage();
        }
    },
    'language' => new class {
        public function list()
        {
            return new FakeCollection([(object) ['code' => 'en', 'label' => 'English']]);
        }
    },
    'outage_update' => new class ($payload) {
        private string $payload;

        public function __construct($payload)
        {
            $this->payload = $payload;
        }

        public function list($params = [])
        {
            return new FakeCollection([
                (object) [
                    'created_at' => '2026-05-21 10:05:00 UTC',
                    'en_summary' => '<b>summary should be escaped</b>',
                    'en_description' => '',
                    'reporter_name' => $this->payload,
                    'begins_at' => null,
                    'finished_at' => null,
                    'state' => null,
                    'type' => null,
                    'impact' => null,
                    'duration' => null,
                ],
            ]);
        }
    },
];

require __DIR__ . '/../../../webui/forms/outage.forms.php';

outage_details(31337);
$html = implode("\n", $xtpl->cells);

if (strpos($html, $payload) !== false) {
    fwrite(STDERR, "Raw reporter_name payload was rendered.\n");
    exit(1);
}

if (strpos($html, h($payload)) === false) {
    fwrite(STDERR, "Escaped reporter_name payload was not rendered.\n");
    exit(1);
}

if (strpos($html, '&lt;b&gt;summary should be escaped&lt;/b&gt;') === false) {
    fwrite(STDERR, "Control summary value was not escaped as expected.\n");
    exit(1);
}

echo "Escaped outage update reporter_name in outage details.\n";
