<?php

use PHPUnit\Framework\TestCase;

class FakeOutageCollection implements IteratorAggregate, Countable
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

class FakeOutageRelation
{
    private FakeOutageCollection $collection;

    public function __construct(array $items = [])
    {
        $this->collection = new FakeOutageCollection($items);
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
    public string $type = 'planned_outage';
    public string $impact = 'network';
    public bool $auto_resolve = false;
    public int $affected_user_count = 0;
    public int $affected_direct_vps_count = 0;
    public int $affected_indirect_vps_count = 0;
    public int $affected_export_count = 0;
    public FakeOutageRelation $entity;
    public FakeOutageRelation $handler;
    public string $en_summary = 'escaped summary';
    public string $en_description = 'escaped description';

    public function __construct()
    {
        $this->entity = new FakeOutageRelation([(object) ['label' => 'vpsAdmin']]);
        $this->handler = new FakeOutageRelation([]);
    }
}

class FakeOutageTemplate
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

final class OutageDetailsReporterNameXssTest extends TestCase
{
    public function testOutageDetailsEscapesReporterNames(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        if (!function_exists('isAdmin')) {
            function isAdmin()
            {
                return true;
            }
        }

        if (!function_exists('isLoggedIn')) {
            function isLoggedIn()
            {
                return true;
            }
        }

        if (!function_exists('tolocaltz')) {
            function tolocaltz($value, $fmt = null)
            {
                return (string) $value;
            }
        }

        if (!function_exists('h')) {
            function h($v)
            {
                if (is_null($v)) {
                    return '';
                }

                return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
            }
        }

        if (!function_exists('boolean_icon')) {
            function boolean_icon($v)
            {
                return $v ? 'yes' : 'no';
            }
        }

        $payload = '<img src=x onerror=alert("outage-reporter-xss")>';

        global $xtpl, $api;

        $xtpl = new FakeOutageTemplate();
        $api = (object) [
            'outage' => new class {
                public function show($id)
                {
                    return new FakeOutage();
                }
            },
            'outage_security_advisory' => null,
            'security_advisory' => null,
            'language' => new class {
                public function list()
                {
                    return new FakeOutageCollection([(object) ['code' => 'en', 'label' => 'English']]);
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
                    return new FakeOutageCollection([
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

        require dirname(__DIR__, 2) . '/forms/outage.forms.php';

        self::assertSame('Planned outage', outage_type_list_label('planned_outage'));
        self::assertSame('Unplanned outage', outage_type_list_label('unplanned_outage'));
        self::assertSame('Planned outage', outage_type_label('planned_outage'));

        outage_details(31337);
        $html = implode("\n", $xtpl->cells);

        self::assertStringNotContainsString($payload, $html);
        self::assertStringContainsString(h($payload), $html);
        self::assertStringContainsString('&lt;b&gt;summary should be escaped&lt;/b&gt;', $html);
    }

    public function testOutageListTitlesUseCompleteMessages(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        require_once dirname(__DIR__, 2) . '/forms/outage.forms.php';

        $planned = [(object) ['type' => 'planned_outage']];
        $unplanned = [(object) ['type' => 'unplanned_outage']];
        $mixed = [
            (object) ['type' => 'planned_outage'],
            (object) ['type' => 'unplanned_outage'],
        ];

        self::assertSame('Planned outages', outage_list_title('upcoming', $planned));
        self::assertSame('Upcoming outages', outage_list_title('upcoming', $unplanned));
        self::assertSame('Upcoming planned and unplanned outages', outage_list_title('upcoming', $mixed));
        self::assertSame('Current planned outages', outage_list_title('current', $planned));
        self::assertSame('Current outages', outage_list_title('current', $unplanned));
        self::assertSame('Current planned and unplanned outages', outage_list_title('current', $mixed));
        self::assertSame('Recently completed planned outages', outage_list_title('recent', $planned));
        self::assertSame('Recently resolved outages', outage_list_title('recent', $unplanned));
        self::assertSame('Recently resolved planned and unplanned outages', outage_list_title('recent', $mixed));
    }

    public function testCzechOutageLinkTranslationsUseNeutralReportTerms(): void
    {
        $po = file_get_contents(
            dirname(__DIR__, 2) . '/lang/locale/cs_CZ.utf8/LC_MESSAGES/vpsAdmin.po'
        );

        self::assertStringContainsString("msgid \"Link outage\"\nmsgstr \"Propojit hlášení\"", $po);
        self::assertStringContainsString("msgid \"Outage ID\"\nmsgstr \"ID hlášení\"", $po);
        self::assertStringContainsString(
            "msgid \"Outage ID must be a number.\"\nmsgstr \"ID hlášení musí být číslo.\"",
            $po
        );
    }
}
