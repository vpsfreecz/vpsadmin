<?php

function vps_run_redirect_path($veid)
{
    $fallback = ($_GET['action'] ?? null) == 'info'
        ? '?page=adminvps&action=info&veid=' . $veid
        : '?page=adminvps';

    $referer = vps_run_referer_target($_SERVER['HTTP_REFERER'] ?? null);
    $current = local_redirect_target($_SERVER['REQUEST_URI'] ?? '', null);

    if ($referer !== null && $current !== null && $referer !== $current) {
        return $referer;
    }

    return $fallback;
}

function vps_run_referer_target($referer)
{
    if (!is_string($referer)) {
        return null;
    }

    $referer = trim($referer);
    if ($referer === '') {
        return null;
    }

    $parts = parse_url($referer);
    if ($parts === false) {
        return null;
    }

    if (!isset($parts['scheme']) && !isset($parts['host'])) {
        return local_redirect_target($referer, null);
    }

    if (!isset($parts['scheme'], $parts['host'])) {
        return null;
    }

    $scheme = strtolower($parts['scheme']);
    if ($scheme !== 'http' && $scheme !== 'https') {
        return null;
    }

    $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? null;
    if ($host === null) {
        return null;
    }

    $refererHost = $parts['host'];
    if (isset($parts['port'])) {
        $refererHost .= ':' . $parts['port'];
    }

    if (strcasecmp($refererHost, $host) !== 0) {
        return null;
    }

    $target = $parts['path'] ?? '/';

    if (isset($parts['query'])) {
        $target .= '?' . $parts['query'];
    }

    if (isset($parts['fragment'])) {
        $target .= '#' . $parts['fragment'];
    }

    return local_redirect_target($target, null);
}
