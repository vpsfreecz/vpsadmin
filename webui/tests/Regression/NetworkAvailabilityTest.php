<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class NetworkAvailabilityTest extends TestCase
{
    public function testAvailableRouteSelectorUsesOnlyAdvertisedNetworkFilter(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        global $api;
        $vps = (object) ['user_id' => 1, 'node' => (object) ['location_id' => 2]];

        foreach ([true, false] as $supported) {
            $resource = new class ($supported) {
                public object $list;
                public array $filters = [];

                public function __construct(bool $supported)
                {
                    $this->list = new class ($supported) {
                        public function __construct(private bool $supported) {}

                        public function getParameters($type)
                        {
                            return (object) ($this->supported ? ['network_enabled' => (object) []] : []);
                        }
                    };
                }

                public function list($filters)
                {
                    $this->filters = $filters;
                    return [(object) ['id' => 3, 'addr' => '192.0.2.3', 'prefix' => 32, 'user_id' => 1]];
                }
            };
            $api = (object) ['ip_address' => $resource];

            self::assertSame([3 => '192.0.2.3/32 (owned)'], get_free_route_list('ipv4', $vps));
            self::assertSame($supported, array_key_exists('network_enabled', $resource->filters));
            if ($supported) {
                self::assertTrue($resource->filters['network_enabled']);
            }
            self::assertSame(false, $resource->filters['assigned_to_interface']);
            self::assertSame(2, $resource->filters['location']);
        }
    }

    public function testStaleDisabledOwnedAssignmentFormHasNoSubmissionControls(): void
    {
        $this->loadUi();
        global $api, $xtpl;
        $api = $this->realClient(false);
        $xtpl = $this->template();
        $_POST = ['vps' => 4, 'network_interface' => 5];

        route_assign_form(3);

        self::assertStringContainsString(
            _('Disabling prevents new allocations and assignments. Existing service continues, and operations already accepted may finish. Detached owned addresses cannot be assigned until the network is enabled again.'),
            $xtpl->text('main.perex')
        );
        self::assertStringNotContainsString('<form', $xtpl->text('main.table'));
        self::assertSame(['ip_address.show'], array_column($api->requests, 'action'));
    }

    public function testNetworkEditorUsesRealClientStateAndAdvertisedCapability(): void
    {
        $this->loadUi();
        global $api, $xtpl;

        foreach ([[true, true], [false, true], [true, false], [false, false], [null, true]] as [$enabled, $supported]) {
            $api = $this->realClient($enabled, $supported);
            $xtpl = $this->template();
            self::assertSame('PUT', $api->network->update->httpMethod());
            self::assertSame($supported, isset($api->network->update->getParameters('input')->enabled));
            $network = $api->network->show(7);
            self::assertInstanceOf(\HaveAPI\Client\ResourceInstance::class, $network);
            self::assertSame($enabled, network_enabled_state($network));

            network_enabled_form(7);

            $html = $xtpl->text('main.table');
            if (!$supported || $enabled === null) {
                self::assertStringNotContainsString('<form', $html);
                continue;
            }

            self::assertStringContainsString('action="?page=cluster&amp;action=network_enabled&amp;network=7" method="post"', $html);
            self::assertStringContainsString('name="enabled" value="' . ($enabled ? '0' : '1') . '"', $html);
            self::assertStringContainsString('name="confirm"', $html);
            self::assertStringContainsString('name="csrf_token"', $html);
            self::assertStringContainsString($enabled ? _('Disable this network') : _('Enable this network'), $html);
            self::assertStringContainsString('192.0.2.0/24 (#7)', $html);
        }
    }

    public function testNetworkInventoryGroupsRealClientPropertiesAndKeepsEditCapability(): void
    {
        $this->loadUi();
        global $api, $xtpl;

        foreach ([[true, true], [false, true], [false, false], [null, false]] as [$enabled, $supported]) {
            $api = $this->realClient($enabled, $supported);
            $xtpl = $this->template();

            networks_list();

            $xpath = $this->xpath($xtpl->text('main.table'));
            $row = $xpath->query('//tr[td[1]/strong="192.0.2.0/24"]')->item(0);
            self::assertNotNull($row);
            self::assertSame(4, $xpath->query('./td', $row)->length);
            self::assertSame(2, $xpath->query('//table[@id="network-list"]/tr')->length);
            self::assertStringContainsString('test network', $row->textContent);
            $properties = $xpath->query('./td[2]/dl[@class="inline network-properties"]', $row)->item(0);
            self::assertNotNull($properties);
            self::assertSame(3, $xpath->query('./dt', $properties)->length);
            self::assertSame(3, $xpath->query('./dd', $properties)->length);
            self::assertSame([_('Type'), _('Managed'), _('Enabled')], array_map(
                static fn($label) => $label->textContent,
                iterator_to_array($xpath->query('./dt', $properties))
            ));
            self::assertSame('Pub', $xpath->query('./dt[1]/following-sibling::dd[1]', $properties)->item(0)->textContent);
            self::assertSame('template/icons/transact_fail.png', $xpath->query('./dt[2]/following-sibling::dd[1]/img/@src', $properties)->item(0)->nodeValue);
            self::assertSame(0, $xpath->query('.//strong', $properties)->length);
            $cell = $xpath->query('./dd[@data-network-enabled]', $properties)->item(0);
            self::assertNotNull($cell);
            self::assertSame(_('Enabled'), $xpath->query('./preceding-sibling::dt[1]', $cell)->item(0)->textContent);
            if ($enabled === null) {
                self::assertSame('-', trim($cell->textContent));
                self::assertSame(0, $xpath->query('.//img|.//a', $cell)->length);
            } else {
                self::assertSame(
                    'template/icons/' . ($enabled ? 'transact_ok.png' : 'transact_fail.png'),
                    $xpath->query('.//img/@src', $cell)->item(0)->nodeValue
                );
                self::assertSame($supported ? 1 : 0, $xpath->query('.//a[contains(@href,"action=network_enabled")]', $cell)->length);
                if ($supported) {
                    self::assertSame(_('Edit'), $xpath->query('.//a', $cell)->item(0)->textContent);
                }
            }
        }
    }

    public function testNetworkCountsKeepZeroDistinctFromMissingWithoutUsingOldFreeArithmetic(): void
    {
        $this->loadUi();
        global $api, $xtpl;

        foreach ([['available_to_users' => 0, 'owned_unassigned' => 1], ['available_to_users' => 13, 'owned_unassigned' => 0], null] as $counters) {
            $api = $this->realClient(true, true, false, $counters);
            $xtpl = $this->template();
            networks_list();
            $html = $xtpl->text('main.table');
            $xpath = $this->xpath($html);
            foreach (['available_to_users', 'owned_unassigned', 'assigned', 'used', 'size'] as $field) {
                $value = $xpath->query('//*[@data-network-count="' . $field . '"]')->item(0);
                self::assertNotNull($value);
                self::assertSame('strong', $value->nodeName);
                self::assertSame('dd', $value->parentNode->nodeName);
                self::assertSame('inline network-usage', $value->parentNode->parentNode->getAttribute('class'));
                $label = $xpath->query('./preceding-sibling::dt[1]/span', $value->parentNode)->item(0);
                self::assertNotNull($label);
                self::assertSame('0', $label->getAttribute('tabindex'));
                self::assertSame(match ($field) {
                    'available_to_users' => _('Available to users'),
                    'owned_unassigned' => _('Owned, not assigned'),
                    'assigned' => _('Assigned'),
                    'used' => _('Registered in vpsAdmin'),
                    'size' => _('Total capacity'),
                }, $label->textContent);
                $expected = match ($field) {
                    'assigned' => '1', 'used' => '2', 'size' => '256',
                    default => $counters === null ? '-' : (string) $counters[$field],
                };
                self::assertSame($expected, trim($value->textContent));
            }
            self::assertSame(4, $xpath->query('//th')->length);
            self::assertSame(5, $xpath->query('//dl[@class="inline network-usage"]/dt')->length);
            self::assertSame(5, $xpath->query('//dl[@class="inline network-usage"]/dd')->length);
            self::assertSame(0, $xpath->query('//dl[@class="inline network-usage"]/dt//strong')->length);
            self::assertStringContainsString(h(_('Properties')), $html);
            self::assertStringContainsString(h(_('IP usage')), $html);
            self::assertStringContainsString(h(_('Actions')), $html);
            self::assertSame(5, $xpath->query('//*[@tabindex="0"]')->length);
            self::assertSame(1, $xpath->query('//a[contains(@href,"action=ip_addresses") and contains(@href,"network=7")]')->length);
            self::assertSame(1, $xpath->query('//a[contains(@href,"action=network_locations") and contains(@href,"network=7")]')->length);
            self::assertStringNotContainsString('254', $html);
            self::assertSame(['network.list'], array_column($api->requests, 'action'));
        }
    }

    public function testLargeCapacityRetainsTrustedNumericUnitMarkup(): void
    {
        $this->loadUi();
        global $api, $xtpl;
        $api = $this->realClient(true);
        $api->responses['network.list'][0]->size = 2000000000000;
        $xtpl = $this->template();
        networks_list();
        $html = $xtpl->text('main.table');
        $xpath = $this->xpath($html);
        $capacity = $xpath->query('//*[@data-network-count="size"]')->item(0);
        self::assertSame('dd', $capacity->parentNode->nodeName);
        self::assertSame('12', $xpath->query('.//sup', $capacity)->item(0)->textContent);
        self::assertStringContainsString('10', $capacity->textContent);
        self::assertStringNotContainsString('&lt;sup', $html);
        self::assertStringNotContainsString('&amp;times;', $html);
    }

    public function testNetworkCountLabelsAndTooltipsAreEscaped(): void
    {
        $this->loadUi();
        global $api, $xtpl;
        $api = $this->realClient(true);
        $api->responses['network.list'][0]->label = '<img src=x onerror=alert(1)> & "network"';
        $xtpl = $this->template();
        networks_list();
        $html = $xtpl->text('main.table');
        $xpath = $this->xpath($html);
        self::assertStringContainsString('&lt;img', $html);
        self::assertSame(0, $xpath->query('//img[@onerror]')->length);
        $description = _('Registered addresses or prefixes with no owner or interface assignment, and not reserved by an operation. Disabled networks contribute zero. Use on a particular VPS also depends on location, network purpose and user limits.');
        $label = $xpath->query('//*[@data-network-count="available_to_users"]/parent::dd/preceding-sibling::dt[1]/span')->item(0);
        self::assertSame($description, $label->getAttribute('title'));
        self::assertSame(_('Available to users') . '. ' . $description, $label->getAttribute('aria-label'));
    }

    public function testIpInventoryPreservesAssignedServiceAndFiltersDetachedActions(): void
    {
        $this->loadUi();
        global $api, $xtpl;
        $_GET['list'] = '1';

        foreach ([[true, false], [false, false], [null, false], [false, true]] as [$enabled, $assigned]) {
            $api = $this->realClient($enabled, true, $assigned);
            $xtpl = $this->template();

            ip_address_list('networking');

            $xpath = $this->xpath($xtpl->text('main.table'));
            $row = $xpath->query('//tr[td[1]="192.0.2.0/24"]')->item(0);
            self::assertNotNull($row);
            self::assertSame($enabled === false ? 'background:#A6A6A6' : '', $row->getAttribute('style'));
            self::assertSame(0, $xpath->query('//th[normalize-space(.)="' . _('Enabled') . '"]')->length);
            $tooltip = $xpath->query('./td[1]/span/@title', $row);
            self::assertSame($enabled === false ? 1 : 0, $tooltip->length);
            if ($enabled === false) {
                self::assertSame(_('This network is disabled for new allocations and assignments. Existing assignments remain usable.'), $tooltip->item(0)->nodeValue);
            }
            self::assertSame(!$assigned && $enabled !== false ? 1 : 0, $xpath->query('.//a[contains(@href,"action=route_assign")]', $row)->length);
            self::assertSame($assigned ? 1 : 0, $xpath->query('.//a[contains(@href,"action=route_unassign")]', $row)->length);
            self::assertSame($assigned ? 1 : 0, $xpath->query('.//a[contains(@href,"page=adminvps")]', $row)->length);
            self::assertSame(1, $xpath->query('.//a[contains(@href,"action=route_edit")]', $row)->length);
        }
    }

    public function testIpDetailUsesRealClientStateWithoutHidingServiceLinks(): void
    {
        $this->loadUi();
        global $api, $xtpl;

        foreach ([[true, false], [false, false], [null, false], [false, true]] as [$enabled, $assigned]) {
            $api = $this->realClient($enabled, true, $assigned);
            $xtpl = $this->template();

            route_edit_form(3);

            $table = $this->xpath($xtpl->text('main.table'));
            $sidebar = $this->xpath($xtpl->text('main.sidebar'));
            $state = $table->query('//tr[td[1]="' . _('Network enabled') . ':"]/td[2]');
            self::assertSame($enabled === null ? 0 : 1, $state->length);
            if ($enabled !== null) {
                self::assertSame($enabled ? _('Enabled') : _('Disabled'), trim($state->item(0)->textContent));
            }
            self::assertSame(!$assigned && $enabled !== false ? 1 : 0, $sidebar->query('//a[contains(@href,"action=route_assign")]')->length);
            self::assertSame($assigned ? 1 : 0, $sidebar->query('//a[contains(@href,"action=route_unassign")]')->length);
            self::assertSame($assigned ? 2 : 0, $table->query('//a[contains(@href,"page=adminvps")]')->length);
            self::assertSame($assigned ? 1 : 0, $table->query('//a[contains(@href,"action=hostaddr_unassign")]')->length);
            self::assertSame(1, $table->query('//a[@data-vpsadmin-doc-id="networking.add-host-addresses"]')->length);
        }
    }

    public function testEnabledAndOldApiAssignmentFormsStillRender(): void
    {
        $this->loadUi();
        global $api, $xtpl;

        foreach ([true, null] as $enabled) {
            $api = $this->realClient($enabled);
            $xtpl = $this->template();

            route_assign_form(3);

            self::assertStringContainsString('action="?page=networking&amp;action=route_assign&amp;id=3&amp;return=" method="post"', $xtpl->text('main.table'));
            self::assertStringContainsString('name="vps"', $xtpl->text('main.table'));
            self::assertSame('', $xtpl->text('main.perex'));
        }
    }

    private function loadUi(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/security.lib.php';
        require_once $root . '/lib/pagination.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/cluster.forms.php';
        require_once $root . '/forms/networking.forms.php';
        $_GET = ['return' => ''];
        $_POST = ['vps' => '', 'network_interface' => ''];
        $_SESSION = ['is_admin' => false, 'csrf_base' => 'network-availability-test'];
        $_SERVER['REQUEST_URI'] = '?page=networking&action=ip_addresses';
    }

    private function template(): XTemplate
    {
        return new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
    }

    private function xpath(string $html): DOMXPath
    {
        $doc = new DOMDocument();
        $doc->loadHTML('<html><body>' . $html . '</body></html>', LIBXML_NOERROR | LIBXML_NOWARNING);
        return new DOMXPath($doc);
    }

    private function realClient(?bool $enabled, bool $supported = true, bool $assigned = false, ?array $counters = ['available_to_users' => 0, 'owned_unassigned' => 1]): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $responses = [];
            public array $requests = [];

            public function directCall(\HaveAPI\Client\Action $action, $params = [], &$time = null)
            {
                $key = $action->getResource()->getName() . '.' . $action->name();
                $this->requests[] = ['action' => $key, 'method' => $action->httpMethod(), 'path' => $action->path(), 'params' => $params];
                if (!array_key_exists($key, $this->responses)) {
                    throw new RuntimeException('Unexpected API request: ' . $key);
                }
                $time = 0.0;
                return (object) [
                    'code' => 200,
                    'body' => (object) [
                        'status' => true,
                        'message' => '',
                        'errors' => (object) [],
                        'response' => (object) [
                            $action->getNamespace('output') => $this->responses[$key],
                            '_meta' => (object) ['path_params' => $action->getLastArgs()],
                        ],
                    ],
                ];
            }
        };
        $resolved = static fn(array $attrs): object => (object) ($attrs + ['_meta' => (object) ['resolved' => true, 'path_params' => [$attrs['id']]]]);
        $network = $resolved([
            'id' => 7, 'address' => '192.0.2.0', 'prefix' => 24, 'label' => 'test network',
            'role' => 'public_access', 'managed' => false, 'size' => 256,
            'used' => 2, 'taken' => 2, 'assigned' => 1, 'owned' => 1, 'primary_location' => null,
        ] + ($counters ?? []) + ($enabled === null ? [] : ['enabled' => $enabled]));
        $user = $resolved(['id' => 1, 'login' => 'test-user']);
        $vps = $resolved(['id' => 4, 'hostname' => 'existing-service']);
        $netif = $resolved(['id' => 5, 'name' => 'eth0', 'vps' => $vps]);
        $ip = $resolved([
            'id' => 3, 'addr' => '192.0.2.3', 'prefix' => 32, 'size' => 1,
            'network' => $network, 'user' => $user, 'network_interface' => $assigned ? $netif : null,
        ]);
        $host = $resolved([
            'id' => 11, 'addr' => '192.0.2.3', 'ip_address' => $ip,
            'reverse_record_value' => null, 'assigned' => true, 'user_created' => false,
        ]);
        $client->responses = [
            'network.show' => $network, 'network.list' => [$network],
            'ip_address.show' => $ip, 'ip_address.list' => [$ip],
            'location.list' => [], 'host_ip_address.list' => $assigned ? [$host] : [],
        ];

        $resourceParam = static fn(string $name, string $label = 'id'): object => (object) [
            'type' => 'Resource', 'resource' => [$name], 'value_id' => 'id', 'value_label' => $label,
        ];
        $fields = [
            'network' => [
                'id' => 'Integer', 'address' => 'String', 'prefix' => 'Integer', 'label' => 'String',
                'role' => 'String', 'managed' => 'Boolean', 'size' => 'Integer',
                'used' => 'Integer', 'taken' => 'Integer', 'assigned' => 'Integer', 'owned' => 'Integer',
                'primary_location' => $resourceParam('location', 'label'),
            ] + array_fill_keys(array_keys($counters ?? []), 'Integer') + ($enabled === null ? [] : ['enabled' => 'Boolean']),
            'ip_address' => [
                'id' => 'Integer', 'addr' => 'String', 'prefix' => 'Integer', 'size' => 'Integer',
                'network' => $resourceParam('network', 'label'), 'user' => $resourceParam('user', 'login'),
                'network_interface' => $resourceParam('network_interface', 'name'),
            ],
            'host_ip_address' => [
                'id' => 'Integer', 'addr' => 'String', 'ip_address' => $resourceParam('ip_address', 'addr'),
                'reverse_record_value' => 'String', 'assigned' => 'Boolean', 'user_created' => 'Boolean',
            ],
            'network_interface' => ['id' => 'Integer', 'name' => 'String', 'vps' => $resourceParam('vps', 'hostname')],
            'vps' => ['id' => 'Integer', 'hostname' => 'String'],
            'user' => ['id' => 'Integer', 'login' => 'String'],
            'location' => ['id' => 'Integer', 'label' => 'String'],
        ];
        $action = static fn(string $namespace, string $method, string $path, string $layout, array $input, array $output): object => (object) [
            'aliases' => [], 'blocking' => false, 'method' => $method, 'path' => $path,
            'input' => (object) ['layout' => 'object', 'namespace' => $namespace, 'parameters' => (object) $input],
            'output' => (object) ['layout' => $layout, 'namespace' => $namespace, 'parameters' => (object) $output],
            'meta' => (object) [],
        ];
        $resources = [];
        foreach ($fields as $name => $types) {
            $parameters = array_map(static fn($type) => is_string($type) ? (object) ['type' => $type] : $type, $types);
            $path = '/v1/' . $name;
            $resources[$name] = (object) [
                'resources' => (object) [],
                'actions' => (object) [
                    'show' => $action($name, 'GET', $path . '/{' . $name . '_id}', 'object', [], $parameters),
                    'list' => $action($name, 'GET', $path, 'object_list', [
                        'from_id' => (object) ['type' => 'Integer'], 'limit' => (object) ['type' => 'Integer', 'default' => 25],
                    ], $parameters),
                ],
            ];
        }
        $resources['network']->actions->update = $action('network', 'PUT', '/v1/network/{network_id}', 'object', $supported ? ['enabled' => (object) ['type' => 'Boolean']] : [], (array) $resources['network']->actions->show->output->parameters);
        $client->setDescription((object) [
            'authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'],
            'resources' => (object) $resources,
        ]);
        return $client;
    }
}
