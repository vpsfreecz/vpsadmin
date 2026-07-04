<?php

use PHPUnit\Framework\TestCase;

require_once dirname(__DIR__, 2) . '/lib/gettext_lang.lib.php';

final class LanguageSelectionTest extends TestCase
{
    private function langs(): array
    {
        return [
            'en_US.utf8' => [
                'code' => 'en_US.utf8',
                'api_code' => 'en',
                'html' => 'en',
                'icon' => 'us',
                'lang' => 'English',
                'aliases' => ['en', 'en-US'],
            ],
            'cs_CZ.utf8' => [
                'code' => 'cs_CZ.utf8',
                'api_code' => 'cs',
                'html' => 'cs',
                'icon' => 'cz',
                'lang' => 'Czech',
                'aliases' => ['cs', 'cs-CZ'],
            ],
        ];
    }

    public function testUserLanguageWinsOverCookieAndBrowserHeader(): void
    {
        self::assertSame(
            'cs_CZ.utf8',
            Lang::detect(
                $this->langs(),
                ['user' => ['language' => 'cs']],
                [Lang::COOKIE_NAME => 'en_US.utf8'],
                ['HTTP_ACCEPT_LANGUAGE' => 'en-US,en;q=0.9']
            )
        );
    }

    public function testCookieWinsOverBrowserHeaderForGuests(): void
    {
        self::assertSame(
            'en_US.utf8',
            Lang::detect(
                $this->langs(),
                [],
                [Lang::COOKIE_NAME => 'en_US.utf8'],
                ['HTTP_ACCEPT_LANGUAGE' => 'cs-CZ,cs;q=0.9']
            )
        );
    }

    public function testAcceptLanguageQualityIsRespected(): void
    {
        self::assertSame(
            'cs_CZ.utf8',
            Lang::detect(
                $this->langs(),
                [],
                [],
                ['HTTP_ACCEPT_LANGUAGE' => 'en-US;q=0.5, cs-CZ;q=0.9']
            )
        );
    }

    public function testLocaleCodesMapToApiLanguageAndHtmlLanguage(): void
    {
        self::assertSame('cs', Lang::apiCodeForLocale($this->langs(), 'cs_CZ.utf8'));
        self::assertSame('cs', Lang::htmlLanguageForLocale($this->langs(), 'cs_CZ.utf8'));
        self::assertSame('cs-cz', Lang::normalizeLanguageTag('cs_CZ.utf8'));
    }

    public function testApiClientOptionsCarrySelectedLanguage(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $options = getApiClientOptions('cs');

        self::assertSame('cs', $options['language']);
    }

    public function testUserLanguageCodeReadsHaveApiLanguageResource(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $user = (object) [
            'language' => (object) [
                'id' => 2,
                'code' => 'cs',
            ],
        ];

        self::assertSame('cs', user_language_code($user));
    }

    public function testUserLanguageCodeResolvesLanguageId(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $user = (object) [
            'language_id' => 2,
        ];
        $langs = [
            (object) ['id' => 1, 'code' => 'en'],
            (object) ['id' => 2, 'code' => 'cs'],
        ];

        self::assertSame('cs', user_language_code($user, $langs));
    }

    public function testUserLanguageCodeDefaultsToEnglish(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        self::assertSame('en', user_language_code((object) []));
    }
}
