<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class DnsTransferReadinessTest extends TestCase
{
    public function testDetachedWarningUsesIncludedParentOwnershipAndExplicitNullOnly(): void
    {
        $this->loadUi();
        global $api;
        $api = $this->client();
        $zone = (object) ['id' => 1, 'user_id' => 7, 'source' => 'external_source'];
        foreach ([
            [['user' => (object) ['id' => 7], 'network_interface' => null], true],
            [['user' => (object) ['id' => 7]], false],
            [['user' => (object) ['id' => 8], 'network_interface' => null], false],
            [['network_interface' => null], false],
            [['user' => (object) ['id' => 7], 'network_interface' => (object) ['id' => 9]], false],
            [['user' => (object) ['id' => 7], 'network_interface' => null, '_meta' => (object) ['resolved' => false]], false],
        ] as [$allocation, $detached]) {
            $attrs = ['id' => 2, 'host_ip_address' => (object) [
                'id' => 3, 'addr' => '2001:db8::5', 'assigned' => false, 'order' => 5,
                'ip_address' => (object) ($allocation + ['_meta' => (object) ['resolved' => true]]),
                '_meta' => (object) ['resolved' => true],
            ]];
            $api->responses['dns_zone_transfer.show'] = (object) $attrs;
            $transfer = $api->dns_zone_transfer->show(2);
            self::assertSame($detached, dnsZoneTransferOwnedDetached($transfer, $zone));
        }
        self::assertSame(['dns_zone_transfer.show'], array_unique(array_column($api->requests, 'action')));
    }

    public function testStaleSuccessAndFailureRemainPendingWithHistoricalEvidenceTimes(): void
    {
        $this->loadUi();
        global $api;
        foreach (['success', 'failed'] as $status) {
            $api = $this->client();
            $api->responses['dns_server_zone_primary_transfer_state.list'] = [(object) [
                'id' => 4, 'dns_server_zone_id' => 3, 'status' => $status,
                'evidence_current' => false, 'reason' => '<script>old failure</script>',
                'last_attempt_kind' => 'ixfr_probe', 'last_attempt_at' => '2026-11-08T11:00:00Z',
                'last_success_at' => '2026-11-08T09:00:00Z', 'reason_observed_at' => '2026-11-08T08:00:00Z',
            ]];
            $html = dnsZoneTransferStatus($this->zone(), $this->transfer(), $this->servers());
            self::assertStringContainsString(_('Pending current evidence'), $html);
            self::assertStringContainsString(_('Previous result'), $html);
            self::assertStringContainsString(_('Last success'), $html);
            self::assertStringNotContainsString('<script>', $html);
        }
    }

    public function testCurrentFailedPathEscapesReasonAndPeerSuccessDoesNotHideIt(): void
    {
        $this->loadUi();
        global $api;
        $api = $this->client();
        $api->responses['dns_server_zone_primary_transfer_state.list'] = [(object) [
            'id' => 4, 'dns_server_zone_id' => 3, 'status' => 'failed', 'evidence_current' => true,
            'reason' => '<script>refused</script>', 'last_attempt_kind' => 'ixfr_probe',
        ]];
        $servers = $this->servers();
        $servers[0]->last_transfer_status = 'success';
        $html = dnsZoneTransferStatus($this->zone(), $this->transfer('failed'), $servers);
        self::assertStringContainsString('&lt;script&gt;refused&lt;/script&gt;', $html);
        self::assertStringNotContainsString('<script>', $html);
        self::assertSame(2, $api->requests[0]['params']['dns_zone_transfer']);
    }

    public function testAbsentPathIsPendingAndOldApiDoesNotCallNewResource(): void
    {
        $this->loadUi();
        global $api;
        $api = $this->client();
        $api->responses['dns_server_zone_primary_transfer_state.list'] = [];
        self::assertStringContainsString(_('Pending first check'), dnsZoneTransferStatus($this->zone(), $this->transfer(), $this->servers()));
        $api = $this->client(false);
        self::assertStringContainsString(_('Transfer readiness is unavailable.'), dnsZoneTransferStatus($this->zone(), $this->transfer(), $this->servers()));
        self::assertSame([], $api->requests);
    }

    public function testMissingPrimaryQueryIsIndependentAndExcludesPeers(): void
    {
        $this->loadUi();
        global $api;
        $api = $this->client();
        $api->responses['dns_zone_transfer.list'] = [];
        self::assertFalse(dnsZoneHasUserPrimary($this->zone()));
        self::assertSame(['dns_zone' => 1, 'peer_type' => 'primary_type', 'limit' => 1], $api->requests[0]['params']);
        $api->responses['dns_zone_transfer.list'] = [(object) ['id' => 2]];
        self::assertTrue(dnsZoneHasUserPrimary($this->zone()));
    }

    public function testSourceKindsAndServingRemainIndependentFromReadiness(): void
    {
        $this->loadUi();
        self::assertSame(_('Historical attempt'), dnsTransferAttemptKindLabel('legacy'));
        self::assertSame(_('Serving'), dnsServingStatusLabel('serving'));
        self::assertSame(_('Unknown'), dnsServingStatusLabel(null));
        self::assertSame(_('BIND refresh'), dnsTransferAttemptKindLabel('refresh'));
    }

    public function testCurrentAggregateSuccessDoesNotReuseHistoricalFailure(): void
    {
        $this->loadUi();
        global $api;
        $api = $this->client();
        $html = dnsZoneTransferStatus($this->zone(), $this->transfer('success'), $this->servers());
        self::assertStringContainsString(_('Successful'), $html);
        self::assertStringNotContainsString(_('Pending current evidence'), $html);
        self::assertSame([], $api->requests);
    }

    public function testOldApiRetainsHistoricalAttemptWithoutClaimingServingHealth(): void
    {
        $this->loadUi();
        $server = (object) [
            'id' => 3, 'serial' => 42, 'loaded_at' => null, 'last_check_at' => null,
            'refresh_at' => null, 'expires_at' => null, 'last_transfer_status' => 'failed',
            'last_transfer_at' => '2026-11-08T08:00:00Z', 'last_transfer_primary_addr' => '192.0.2.5',
            'last_transfer_reason' => '<script>connection refused</script>',
        ];
        $html = dnsServerZoneState($server);
        self::assertStringContainsString(_('Unknown'), $html);
        self::assertStringContainsString(_('Last transfer'), $html);
        self::assertStringContainsString(_('Failed'), $html);
        self::assertStringContainsString('&lt;script&gt;connection refused&lt;/script&gt;', $html);
        self::assertStringNotContainsString('<script>', $html);
    }

    private function loadUi(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/forms/dns.forms.php';
        $_SERVER['REQUEST_URI'] = '?page=dns&action=zone_show&id=1';
        $_SESSION = ['time_zone' => 'UTC'];
    }

    private function zone(): object
    {
        return (object) ['id' => 1, 'source' => 'external_source'];
    }

    private function transfer(string $status = 'pending'): object
    {
        return (object) [
            'id' => 2, 'transfer_check_status' => $status, 'transfer_check_success_count' => 0,
            'transfer_check_failed_count' => $status === 'failed' ? 1 : 0,
            'transfer_check_pending_count' => $status === 'pending' ? 1 : 0,
            'last_transfer_check_at' => '2026-11-08T11:00:00Z',
        ];
    }

    private function servers(): array
    {
        return [(object) ['id' => 3, 'dns_server' => (object) ['name' => 'ns.example.test']]];
    }

    private function client(bool $current = true): \HaveAPI\Client
    {
        $client = new class ('https://api.example.test') extends \HaveAPI\Client {
            public array $responses = [];
            public array $requests = [];

            public function directCall(\HaveAPI\Client\Action $action, $params = [], &$time = null)
            {
                $key = $action->getResource()->getName() . '.' . ($action->name() === 'index' ? 'list' : $action->name());
                $this->requests[] = ['action' => $key, 'params' => $params];
                if (!array_key_exists($key, $this->responses)) {
                    throw new RuntimeException('Unexpected API request: ' . $key);
                }
                $time = 0.0;
                return (object) ['code' => 200, 'body' => (object) [
                    'status' => true, 'message' => '', 'errors' => (object) [],
                    'response' => (object) [
                        $action->getNamespace('output') => $this->responses[$key],
                        '_meta' => (object) ['path_params' => $action->getLastArgs()],
                    ],
                ]];
            }
        };
        $resources = [];
        foreach (['dns_zone_transfer', 'dns_server_zone_primary_transfer_state'] as $name) {
            if (!$current && $name === 'dns_server_zone_primary_transfer_state') {
                continue;
            }
            $actions = [];
            foreach (['show' => 'object', 'list' => 'object_list'] as $action => $layout) {
                $actions[$action === 'list' ? 'index' : $action] = (object) [
                    'aliases' => $action === 'list' ? ['list'] : [], 'blocking' => false, 'method' => 'GET',
                    'path' => '/v1/' . $name . ($action === 'show' ? '/{id}' : ''),
                    'input' => (object) ['layout' => 'object', 'namespace' => $name, 'parameters' => (object) [
                        'dns_zone' => (object) ['type' => 'Integer'],
                        'peer_type' => (object) ['type' => 'String'],
                        'dns_zone_transfer' => (object) ['type' => 'Integer'],
                        'limit' => (object) ['type' => 'Integer'],
                    ]],
                    'output' => (object) ['layout' => $layout, 'namespace' => $name, 'parameters' => (object) [
                        'id' => (object) ['type' => 'Integer'],
                        'dns_server_zone_id' => (object) ['type' => 'Integer'],
                        'evidence_current' => (object) ['type' => 'Boolean'],
                    ]],
                    'meta' => (object) [],
                ];
            }
            $resources[$name] = (object) ['resources' => (object) [], 'actions' => (object) $actions];
        }
        $client->setDescription((object) [
            'authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'],
            'resources' => (object) $resources,
        ]);
        return $client;
    }
}
