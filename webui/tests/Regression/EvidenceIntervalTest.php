<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class EvidenceIntervalTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/incidents.forms.php';
        global $xtpl;
        $xtpl = new XTemplate($root . '/template/template.html');
        $_GET = [];
        date_default_timezone_set('Europe/Prague');
    }

    private function client(?int $next = 25, bool $available = true, bool $measured = true): object
    {
        $rows = new class ($next, $available, $measured) extends ArrayObject {
            public function __construct(private ?int $next, private bool $available, bool $measured)
            {
                parent::__construct([(object) ['from_at' => '2026-11-25T12:00:01.000001Z',
                    'to_at' => '2026-11-25T12:00:03.000001Z', 'credit_us' => 2000000,
                    'measurement' => $measured ? 'rtnl_latency' : null, 'peak_unit' => $measured ? 'microseconds' : null, 'peak_value' => $measured ? 3000000 : null, 'peak_is_lower_bound' => $measured ? true : null]]);
            }

            public function getMeta(): array
            {
                return ['available' => $this->available, 'window_complete' => false, 'total_count' => 26, 'next_offset' => $this->next,
                    'condition_measurement' => 'rtnl_latency', 'condition_operator' => 'gt', 'condition_value' => 1000000, 'condition_unit' => 'microseconds'];
            }
        };
        return new class ($rows) {
            public array $requests = [];

            public function __construct(private ArrayObject $rows) {}

            public function incident_report($id): object
            {
                $this->requests[] = $id;
                return (object) ['evidence_interval' => new class ($this->rows) {
                    public bool $index = true;
                    public array $args = [];

                    public function __construct(private ArrayObject $rows) {}

                    public function index(array $args): ArrayObject
                    {
                        $this->args = $args;
                        return $this->rows;
                    }
                }];
            }
        };
    }

    public function testOffsetsAndLowerBoundRemainVisibleWithEscapedPagination(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $_GET['evidence_offset'] = '<script>';
        incident_evidence_intervals((object) ['id' => '7"><script>', 'codename' => 'rtnl_latency']);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('incident-report.evidence-intervals', $html);
        self::assertStringContainsString('2026-11-25 13:00:01.000001 +01:00', $html);
        self::assertStringContainsString('2026-11-25 13:00:03.000001 +01:00', $html);
        self::assertStringContainsString('RTNL latency: ≥3 s', $html);
        self::assertStringContainsString('1 of 26', $html);
        self::assertStringContainsString('evidence_offset=25', $html);
        self::assertStringContainsString('id=7%22%3E%3Cscript%3E', $html);
        self::assertStringNotContainsString('<script>', $html);
        self::assertStringContainsString('lower bound', $html);
    }

    public function testFinalPageHasPreviousOnly(): void
    {
        global $api, $xtpl;
        $api = $this->client(null);
        // Availability comes from the saved evidence API, not a signal codename.
        $_GET['evidence_offset'] = 25;
        incident_evidence_intervals((object) ['id' => 7, 'codename' => 'rtnl_latency']);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('evidence_offset=0', $html);
        self::assertStringNotContainsString('>Next<', $html);
    }
    public function testCommonTimelineAllowsAbsentMeasurementAndShowsSavedCondition(): void
    {
        global $api, $xtpl;
        $api = $this->client(null, true, false);
        incident_evidence_intervals((object) ['id' => 7, 'codename' => 'future_signal']);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Not available', $html);
        self::assertStringContainsString('RTNL latency is greater than 1 s', $html);
        self::assertStringNotContainsString('≥', $html);
    }

    public function testOrdinaryUnavailableReportHasNoTimeline(): void
    {
        global $api, $xtpl;
        $api = $this->client(null, false);
        incident_evidence_intervals((object) ['id' => 7, 'codename' => null]);
        self::assertStringNotContainsString('incident-report.evidence-intervals', $xtpl->text('main.table'));
    }

    public function testTypedDurationFormattingPreservesMicrosecondsAndCzechSeparator(): void
    {
        $oldLocale = $GLOBALS['CURRENTLOCALE'] ?? null;
        try {
            $GLOBALS['CURRENTLOCALE'] = 'en_US.utf8';
            self::assertSame('1.000001', incident_evidence_seconds(1000001));
            self::assertSame('9223372036854.775807', incident_evidence_seconds(PHP_INT_MAX));
            self::assertSame('0 s', incident_evidence_quantity(0, 'microseconds'));
            self::assertSame('1.000001 s', incident_evidence_quantity(1000001, 'microseconds'));
            self::assertNull(incident_evidence_quantity(null, null));
            self::assertNull(incident_evidence_quantity(1000001, 'unknown'));
            self::assertNull(incident_evidence_measurement('unknown'));
            $GLOBALS['CURRENTLOCALE'] = 'cs_CZ.utf8';
            self::assertSame('1,000001', incident_evidence_seconds(1000001));
        } finally {
            if ($oldLocale === null) {
                unset($GLOBALS['CURRENTLOCALE']);
            } else {
                $GLOBALS['CURRENTLOCALE'] = $oldLocale;
            }
        }
    }

}
