<?php

use PHPUnit\Framework\TestCase;

class ApiParamChoicesTemplate
{
    public array $selects = [];

    public function form_add_select_pure($name, $choices, $value)
    {
        $this->selects[] = [$name, $choices, $value];
    }
}

final class ApiParamChoicesTest extends TestCase
{
    public function testMappedChoiceMetadataRendersAsSelectOptions(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        global $xtpl;

        $xtpl = new ApiParamChoicesTemplate();
        $desc = (object) [
            'type' => 'String',
            'validators' => (object) [
                'include' => (object) [
                    'values' => (object) [
                        'planned_outage' => 'Planned outage',
                        'unplanned_outage' => 'Unplanned outage',
                    ],
                ],
            ],
        ];

        api_param_to_form_pure('type', $desc, 'planned_outage', null, true);

        self::assertSame([
            [
                'type',
                [
                    '' => '---',
                    'planned_outage' => 'Planned outage',
                    'unplanned_outage' => 'Unplanned outage',
                ],
                'planned_outage',
            ],
        ], $xtpl->selects);
    }
}
