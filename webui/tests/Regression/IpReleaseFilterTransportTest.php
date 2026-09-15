<?php

use PHPUnit\Framework\TestCase;

require_once dirname(__DIR__, 2) . '/forms/ip_release.forms.php';

final class IpReleaseFilterTransportTest extends TestCase
{
    public function testDefaultAndMultiSelectFiltersSurviveThePinnedClientGetTransport(): void
    {
        $cases = [
            [
                ['versions' => [4], 'networks' => [], 'locations' => [], 'access' => 'public_access'],
                ['versions' => '4', 'networks' => '', 'locations' => '', 'access' => 'public_access'],
            ],
            [
                ['versions' => [4, 6], 'networks' => [10, 20], 'locations' => [1, 2], 'access' => 'all', 'user' => 42],
                ['versions' => '4,6', 'networks' => '10,20', 'locations' => '1,2', 'access' => 'all', 'user' => '42'],
            ],
        ];
        foreach ($cases as [$filters, $expected]) {
            $client = new \HaveAPI\Client('https://example.test');
            $description = (object) [
                'method' => 'GET',
                'input' => (object) ['parameters' => (object) [
                    'versions' => (object) ['type' => 'String'],
                    'networks' => (object) ['type' => 'String'],
                    'locations' => (object) ['type' => 'String'],
                    'access' => (object) ['type' => 'String'],
                    'user' => (object) ['type' => 'Integer'],
                ]],
            ];
            $action = new \HaveAPI\Client\Action($client, $client, 'Candidates', $description, []);
            $params = new ReflectionMethod($client, 'coerceAndValidateInput');
            $clean = $params->invoke($client, $action, ip_release_candidate_params($filters));
            (new ReflectionProperty($client, 'queryParams'))->setValue($client, []);
            $request = new class {
                public $uri = 'https://example.test/ip_release_campaigns/candidates';

                public function send()
                {
                    return $this->uri;
                }
            };
            // Exercise the installed client's query encoder without a network request.
            $url = (new ReflectionMethod($client, 'sendRequest'))->invoke(
                $client,
                $request,
                $action,
                ['ip_release_campaign' => $clean],
            );
            parse_str(parse_url($url, PHP_URL_QUERY), $decoded);
            self::assertSame($expected, $decoded['ip_release_campaign']);
        }
    }
}
