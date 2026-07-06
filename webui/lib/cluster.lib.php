<?php

/*
    ./lib/cluster.lib.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

class SystemConfig implements Iterator
{
    private $api;
    private $cfg;
    private $categories;
    private $catIterator;
    private $options;
    private $optIterator;
    private $language;

    public function __construct($api, $forceLoad = false, $language = null)
    {
        $this->api = $api;
        $this->language = $language;

        if (!$this->language && function_exists('webui_current_api_language')) {
            $this->language = webui_current_api_language($GLOBALS['langs'] ?? null);
        }

        $this->loadConfig($forceLoad);
        $this->setupIterator();
    }

    public function get($cat, $name)
    {
        return $this->cfg[$cat][$name]['value'];
    }

    public function getLocalized($cat, $name)
    {
        return $this->cfg[$cat][$name]['localized_value'] ?? $this->get($cat, $name);
    }

    public function getType($cat, $name)
    {
        return $this->cfg[$cat][$name]['type'];
    }

    public function reload()
    {
        $this->loadConfig(true);
        $this->setupIterator();
    }

    protected function loadConfig($force)
    {
        $cacheKey = $this->language ?: '_default';

        if ($force) {
            unset($_SESSION['sysconfig_by_language']);
        }

        if (!$force && isset($_SESSION['sysconfig_by_language'][$cacheKey])) {
            return $this->cfg = $_SESSION['sysconfig_by_language'][$cacheKey];
        }

        $this->cfg = $this->fetchConfig();
        unset($_SESSION['sysconfig']);
        $_SESSION['sysconfig_by_language'][$cacheKey] = $this->cfg;
    }

    protected function fetchConfig()
    {
        $cfg = [];

        $options = $this->api->system_config->index();

        foreach ($options as $opt) {
            if (!array_key_exists($opt->category, $cfg)) {
                $cfg[$opt->category] = [];
            }

            $cfg[$opt->category][$opt->name] = $opt->attributes();
        }

        return $cfg;
    }

    protected function setupIterator()
    {
        $this->categories = new ArrayObject($this->cfg);
        $this->catIterator = $this->categories->getIterator();

        $this->options = new ArrayObject($this->catIterator->current());
        $this->optIterator = $this->options->getIterator();
    }

    /* Iterator methods */
    public function current(): mixed
    {
        return $this->optIterator->current()['value'];
    }

    public function key(): mixed
    {
        return $this->catIterator->key() . ':' . $this->optIterator->key();
    }

    public function next(): void
    {
        $this->optIterator->next();

        if (!$this->optIterator->valid()) {
            $this->catIterator->next();

            if (!$this->catIterator->valid()) {
                return;
            }

            $this->options = new ArrayObject($this->catIterator->current());
            $this->optIterator = $this->options->getIterator();
        }
    }

    public function rewind(): void
    {
        $this->setupIterator();
    }

    public function valid(): bool
    {
        return $this->catIterator->valid() && $this->optIterator->valid();
    }
}
