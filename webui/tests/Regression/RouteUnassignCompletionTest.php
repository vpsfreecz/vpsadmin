<?php

use PHPUnit\Framework\TestCase;

final class RouteUnassignCompletionTest extends TestCase
{
    public function testRouteIsFreedOnlyAfterSuccessfulDisown(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/networking.forms.php';

        foreach (['pending', 'failed', 'removed'] as $expected) {
            $ip = new class {
                public int $freeCalls = 0;
                public function update($params)
                {
                    return new class {
                        public function getApiResponse()
                        {
                            return $this;
                        }
                        public function getMeta()
                        {
                            return (object) ['action_state_id' => 42];
                        }
                    };
                }
                public function free()
                {
                    $this->freeCalls++;
                }
            };
            $api = new class ($expected) {
                public function __construct(private string $state) {}
                public function action_state($id)
                {
                    return $this;
                }
                public function poll($params)
                {
                    return $this;
                }
                public function getResponse()
                {
                    return (object) [
                        'finished' => $this->state !== 'pending',
                        'status' => $this->state === 'removed',
                    ];
                }
            };

            $result = route_unassign_address($api, $ip, true);
            self::assertSame($expected, $result['state']);
            self::assertSame($expected === 'removed' ? 1 : 0, $ip->freeCalls);
            if ($expected !== 'removed') {
                self::assertSame(42, $result['chain']);
            }
        }
    }

    public function testOrdinaryUnassignmentDoesNotDisown(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/networking.forms.php';
        $ip = new class {
            public int $freeCalls = 0;
            public function free()
            {
                $this->freeCalls++;
            }
        };
        self::assertSame(['state' => 'removed'], route_unassign_address(null, $ip, false));
        self::assertSame(1, $ip->freeCalls);
    }
}
