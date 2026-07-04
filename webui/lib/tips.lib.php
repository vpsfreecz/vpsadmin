<?php

const WEBUI_TIP_TIME_ZONE_SETTINGS = 'time_zone_settings_v1';

function webui_tip_settings($namespace)
{
    global $api;

    if (!$api->webui_user_setting) {
        return [];
    }

    try {
        $settings = $api->webui_user_setting->list([
            'namespace' => $namespace,
            'limit' => 1000,
        ]);

    } catch (\HaveAPI\Client\Exception\Base $e) {
        return [];
    }

    $ret = [];

    foreach ($settings as $setting) {
        $ret[$setting->key] = $setting;
    }

    return $ret;
}

function webui_tip_append_script($settings)
{
    global $xtpl;

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '')
        . '<script type="text/javascript">window.vpsAdminTips = '
        . webui_json($settings)
        . ';</script>'
        . '<script type="text/javascript" src="js/tips.js"></script>'
    );
}

function webui_server_equivalent_time_zones()
{
    static $cache = [];

    if (isset($cache[VPSADMIN_SERVER_TIME_ZONE])) {
        return $cache[VPSADMIN_SERVER_TIME_ZONE];
    }

    $ret = [];
    $referenceTime = time();

    foreach (DateTimeZone::listIdentifiers() as $timeZone) {
        if (time_zones_have_same_offsets($timeZone, VPSADMIN_SERVER_TIME_ZONE, $referenceTime)) {
            $ret[] = $timeZone;
        }
    }

    $cache[VPSADMIN_SERVER_TIME_ZONE] = $ret;
    return $ret;
}

function webui_render_time_zone_tip($settings)
{
    global $xtpl;

    if (isset($settings[WEBUI_TIP_TIME_ZONE_SETTINGS])) {
        return false;
    }

    if (!empty($_SESSION['user']['time_zone'])) {
        return false;
    }

    $profileUrl = '?page=adminm&section=members&action=edit&id='
        . rawurlencode((string) $_SESSION['user']['id']);

    $xtpl->sbar_add_fragment(
        '<div class="webui-tip webui-tip-hidden"'
        . ' data-webui-tip-id="' . h(WEBUI_TIP_TIME_ZONE_SETTINGS) . '"'
        . ' data-webui-tip-namespace="tips"'
        . ' data-server-time-zone="' . h(VPSADMIN_SERVER_TIME_ZONE) . '">'
        . '<button type="button" class="webui-tip-close"'
        . ' data-webui-tip-action="dismiss"'
        . ' title="' . h(_('Dismiss')) . '">x</button>'
        . '<h3>' . h(_('Time zone')) . '</h3>'
        . '<p>'
        . h(_('vpsAdmin can show dates and times in your local time zone.'))
        . '</p>'
        . '<p>'
        . h(_('Your browser reports')) . ' '
        . '<strong class="webui-tip-browser-time-zone"></strong>. '
        . h(_('The server default is')) . ' '
        . '<strong>' . h(VPSADMIN_SERVER_TIME_ZONE) . '</strong>.'
        . '</p>'
        . '<p class="webui-tip-actions">'
        . '<button type="button" data-webui-tip-action="use-browser-time-zone">'
        . h(_('Use browser time zone'))
        . '</button>'
        . '<button type="button" data-webui-tip-action="dismiss">'
        . h(_('Keep server default'))
        . '</button>'
        . '</p>'
        . '<p class="webui-tip-profile">'
        . '<a href="' . h($profileUrl) . '">' . h(_('Edit profile')) . '</a>'
        . '</p>'
        . '<p class="webui-tip-error"></p>'
        . '</div>'
    );

    return true;
}

function webui_render_sidebar_tips()
{
    if (
        !isLoggedIn()
        || !empty($_SESSION['context_switch'])
        || empty($_SESSION['user']['id'])
    ) {
        return;
    }

    $settings = webui_tip_settings('tips');

    $hasTips = webui_render_time_zone_tip($settings);

    if (!$hasTips) {
        return;
    }

    webui_tip_append_script([
        'validTimeZones' => DateTimeZone::listIdentifiers(),
        'serverEquivalentTimeZones' => webui_server_equivalent_time_zones(),
        'messages' => [
            'saving' => _('Saving...'),
            'saveTipFailed' => _('Unable to save this tip. Please try again.'),
            'saveTimeZoneFailed' => _('Unable to save the time zone. Please edit your profile.'),
            'syncTimeZoneFailed' => _('Unable to refresh the time zone. Please reload the page.'),
        ],
    ]);
}
