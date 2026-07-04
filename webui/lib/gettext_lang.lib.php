<?php

class Lang
{
    private $current_lang;
    private $xtpl;
    private $langs;
    private $api;

    public const DEFAULT_LOCALE = 'en_US.utf8';
    public const DEFAULT_API_LANGUAGE = 'en';
    public const COOKIE_NAME = 'vpsAdmin-l_code';
    public const c_name = 'vpsAdmin-l_code';

    public function __construct($langs, &$xtpl, $api = null, $initialLocale = null)
    {
        $this->langs = $langs;
        $this->xtpl  = $xtpl;
        $this->api = $api;

        $this->set_current_lang($initialLocale ?: self::detect($langs), false);
    }

    public static function detect($langs, $session = null, $cookies = null, $server = null)
    {
        $session ??= $_SESSION;
        $cookies ??= $_COOKIE;
        $server ??= $_SERVER;

        $userLanguage = $session['user']['language'] ?? null;
        if ($userLanguage) {
            $locale = self::localeForApiCode($langs, $userLanguage);
            if ($locale) {
                return $locale;
            }
        }

        $cookieLocale = $cookies[self::COOKIE_NAME] ?? null;
        if ($cookieLocale && isset($langs[$cookieLocale])) {
            return $cookieLocale;
        }

        $acceptedLocale = self::localeFromAcceptLanguage(
            $langs,
            $server['HTTP_ACCEPT_LANGUAGE'] ?? ''
        );
        if ($acceptedLocale) {
            return $acceptedLocale;
        }

        return isset($langs[self::DEFAULT_LOCALE])
            ? self::DEFAULT_LOCALE
            : array_key_first($langs);
    }

    public static function localeForApiCode($langs, $apiCode)
    {
        foreach ($langs as $locale => $lang) {
            if (($lang['api_code'] ?? self::localeToApiCode($locale)) == $apiCode) {
                return $locale;
            }
        }

        return null;
    }

    public static function apiCodeForLocale($langs, $locale)
    {
        if (!isset($langs[$locale])) {
            return self::DEFAULT_API_LANGUAGE;
        }

        return $langs[$locale]['api_code'] ?? self::localeToApiCode($locale);
    }

    public static function htmlLanguageForLocale($langs, $locale)
    {
        if (!isset($langs[$locale])) {
            return self::DEFAULT_API_LANGUAGE;
        }

        return $langs[$locale]['html'] ?? self::apiCodeForLocale($langs, $locale);
    }

    public static function currentApiLanguage($langs = null)
    {
        if (isset($_SESSION['user']['language']) && $_SESSION['user']['language']) {
            return $_SESSION['user']['language'];
        }

        if ($langs) {
            return self::apiCodeForLocale($langs, self::detect($langs));
        }

        return self::DEFAULT_API_LANGUAGE;
    }

    public static function localeFromAcceptLanguage($langs, $header)
    {
        if (!is_string($header) || trim($header) === '') {
            return null;
        }

        $accepted = [];

        foreach (explode(',', $header) as $index => $part) {
            $pieces = array_map('trim', explode(';', trim($part)));
            $tag = array_shift($pieces);

            if ($tag === '' || $tag === '*') {
                continue;
            }

            $quality = 1.0;
            foreach ($pieces as $piece) {
                if (preg_match('/^q=([0-9.]+)$/', $piece, $matches)) {
                    $quality = max(0.0, min(1.0, (float) $matches[1]));
                }
            }

            if ($quality <= 0.0) {
                continue;
            }

            $accepted[] = [$quality, $index, $tag];
        }

        usort($accepted, function ($a, $b) {
            if ($a[0] == $b[0]) {
                return $a[1] <=> $b[1];
            }

            return $a[0] > $b[0] ? -1 : 1;
        });

        foreach ($accepted as $candidate) {
            $locale = self::localeForLanguageTag($langs, $candidate[2]);

            if ($locale) {
                return $locale;
            }
        }

        return null;
    }

    public static function localeForLanguageTag($langs, $tag)
    {
        $tag = self::normalizeLanguageTag($tag);
        $primary = explode('-', $tag)[0];

        foreach ($langs as $locale => $lang) {
            $tags = [
                self::normalizeLanguageTag($locale),
                self::normalizeLanguageTag(self::localeWithoutEncoding($locale)),
                self::normalizeLanguageTag($lang['api_code'] ?? self::localeToApiCode($locale)),
            ];

            foreach ($lang['aliases'] ?? [] as $alias) {
                $tags[] = self::normalizeLanguageTag($alias);
            }

            $tags = array_unique(array_filter($tags));

            if (in_array($tag, $tags, true)) {
                return $locale;
            }

            if ($primary && in_array($primary, $tags, true)) {
                return $locale;
            }
        }

        return null;
    }

    public static function normalizeLanguageTag($tag)
    {
        $tag = (string) $tag;
        $tag = preg_replace('/\\.(.*)$/', '', $tag);
        $tag = str_replace('_', '-', strtolower($tag));
        $parts = explode('-', $tag);

        return implode('-', array_filter($parts));
    }

    public static function activate($locale)
    {
        @putenv("LC_ALL=" . $locale);
        T_setlocale(LC_ALL, $locale);
        T_bindtextdomain("vpsAdmin", WEBUI_ROOT . "/lang/locale/");
        T_bind_textdomain_codeset("vpsAdmin", "UTF-8");
        T_textdomain("vpsAdmin");
    }

    public function lang_switcher()
    {
        foreach ($this->langs as $lang) {
            if ($lang["code"] == $this->current_lang) {
                $class = "chosen";
            } else {
                $class = "";
            }

            $this->xtpl->lang_add(
                $lang["code"],
                $lang["icon"],
                $lang["lang"],
                $class,
                $this->languageSwitchTokenParam()
            );
        }
    }
    // $newlang = $lang['code']
    public function change($newlang)
    {
        if (isset($this->langs[$newlang])) {
            if (isLoggedIn()) {
                csrf_check('language');
            }

            $this->set_current_lang($newlang);
            $this->storeSessionLanguage($newlang);
            $this->persistUserLanguage($newlang);

            redirect($this->xtpl->get_prev_url());

            return true;
        } else {
            echo _("ERROR: Language not found");

            return false;
        }
    }

    public function set_current_lang($newlang, $persistCookie = true)
    {
        $this->current_lang = $newlang;

        self::activate($newlang);

        if ($persistCookie && !headers_sent()) {
            $opts = [
                'expires' => time() + 86400 * 365,
                'path' => '/',
            ];

            if (function_exists('isHttps') && isHttps()) {
                $opts['secure'] = true;
            }

            setcookie(self::COOKIE_NAME, $this->current_lang, $opts);
        }
    }

    private static function localeWithoutEncoding($locale)
    {
        return preg_replace('/\\..*$/', '', (string) $locale);
    }

    private static function localeToApiCode($locale)
    {
        return explode('_', self::localeWithoutEncoding($locale))[0];
    }

    private function languageSwitchTokenParam()
    {
        if (!isLoggedIn()) {
            return '';
        }

        return '&t=' . rawurlencode(csrf_token('language'));
    }

    private function storeSessionLanguage($locale)
    {
        if (!isset($_SESSION['user'])) {
            return;
        }

        $_SESSION['user']['language'] = self::apiCodeForLocale($this->langs, $locale);

        if ($this->api) {
            $this->api->setLanguage($_SESSION['user']['language']);
            $this->api->setup(true);
            $_SESSION['api_description'] = $this->api->getDescription();
        }
    }

    private function persistUserLanguage($locale)
    {
        if (!isLoggedIn() || ($_SESSION['context_switch'] ?? false)) {
            return;
        }

        if (!$this->api) {
            return;
        }

        $apiCode = self::apiCodeForLocale($this->langs, $locale);
        $langId = lang_id_by_code($apiCode);

        if (!$langId) {
            notify_user(
                _('Language preference was not saved'),
                _('Selected language is not available in the API.')
            );
            return;
        }

        $this->api->user->show($_SESSION['user']['id'])->update([
            'language' => $langId,
        ]);
    }

    public function get_current_lang()
    {
        return $this->current_lang;
    }
}

function webui_current_api_language($langs = null)
{
    return Lang::currentApiLanguage($langs);
}

function webui_locale_for_api_language($apiCode, $langs = null)
{
    if (!$langs) {
        return Lang::DEFAULT_LOCALE;
    }

    return Lang::localeForApiCode($langs, $apiCode) ?: Lang::DEFAULT_LOCALE;
}
