<?php

use PHPUnit\Framework\TestCase;

if (!function_exists('webui_current_api_language')) {
    function webui_current_api_language($langs = null)
    {
        return $_SESSION['spec_api_language'] ?? 'en';
    }
}

class SystemConfigLocalizationOption
{
    public function __construct(
        public string $category,
        public string $name,
        public string $type,
        public string $value,
        public ?string $localized_value = null,
    ) {}

    public function attributes()
    {
        return [
            'category' => $this->category,
            'name' => $this->name,
            'type' => $this->type,
            'value' => $this->value,
            'localized_value' => $this->localized_value,
        ];
    }
}

class SystemConfigLocalizationResource
{
    public int $calls = 0;

    public function __construct(private array $options) {}

    public function index()
    {
        $this->calls++;
        return $this->options;
    }
}

class SystemConfigLocalizationApi
{
    public SystemConfigLocalizationResource $system_config;

    public function __construct(array $options)
    {
        $this->system_config = new SystemConfigLocalizationResource($options);
    }
}

final class SystemConfigLocalizationTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
    }

    public function testReturnsLocalizedValueFromApiResponse(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/cluster.lib.php';

        $_SESSION['spec_api_language'] = 'cs';
        $api = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption(
                'webui',
                'noticeboard',
                'Hash',
                "---\nen: English notice\ncs: Ceska nastenka\n",
                'Ceska nastenka'
            ),
        ]);

        $config = new SystemConfig($api);

        self::assertSame('Ceska nastenka', $config->getLocalized('webui', 'noticeboard'));
        self::assertSame(1, $api->system_config->calls);
    }

    public function testCachesConfigPerLanguage(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/cluster.lib.php';

        $_SESSION['spec_api_language'] = 'cs';
        $apiCs = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw cs', 'Cesky sidebar'),
        ]);
        $configCs = new SystemConfig($apiCs);

        $_SESSION['spec_api_language'] = 'en';
        $apiEn = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw en', 'English sidebar'),
        ]);
        $configEn = new SystemConfig($apiEn);

        $_SESSION['spec_api_language'] = 'cs';
        $apiCsCached = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'wrong', 'Wrong'),
        ]);
        $configCsCached = new SystemConfig($apiCsCached);

        self::assertSame('Cesky sidebar', $configCs->getLocalized('webui', 'sidebar'));
        self::assertSame('English sidebar', $configEn->getLocalized('webui', 'sidebar'));
        self::assertSame('Cesky sidebar', $configCsCached->getLocalized('webui', 'sidebar'));
        self::assertSame(0, $apiCsCached->system_config->calls);
    }

    public function testForcedReloadClearsAllLanguageCaches(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/cluster.lib.php';

        $_SESSION['spec_api_language'] = 'cs';
        new SystemConfig(new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw cs', 'Stary sidebar'),
        ]));

        $_SESSION['spec_api_language'] = 'en';
        new SystemConfig(new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw en', 'Old sidebar'),
        ]));

        $_SESSION['spec_api_language'] = 'cs';
        new SystemConfig(new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw cs', 'Novy sidebar'),
        ]), true);

        $_SESSION['spec_api_language'] = 'en';
        $apiEn = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Hash', 'raw en', 'New sidebar'),
        ]);
        $configEn = new SystemConfig($apiEn);

        self::assertSame('New sidebar', $configEn->getLocalized('webui', 'sidebar'));
        self::assertSame(1, $apiEn->system_config->calls);
    }

    public function testFallsBackToValueWhenLocalizedValueIsUnavailable(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/cluster.lib.php';

        $api = new SystemConfigLocalizationApi([
            new SystemConfigLocalizationOption('webui', 'sidebar', 'Text', 'Legacy sidebar'),
        ]);

        $config = new SystemConfig($api);

        self::assertSame('Legacy sidebar', $config->getLocalized('webui', 'sidebar'));
    }
}
