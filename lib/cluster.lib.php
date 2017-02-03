<?php
/*
    ./lib/cluster.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

class SystemConfig implements Iterator {
	public function __construct($api, $forceLoad = false) {
		$this->api = $api;

		$this->loadConfig($forceLoad);
		$this->setupIterator();
	}

	public function get($cat, $name) {
		return $this->cfg[$cat][$name]['value'];
	}

	public function getType($cat, $name) {
		return $this->cfg[$cat][$name]['type'];
	}

	public function reload() {
		$this->loadConfig(true);
		$this->setupIterator();
	}

	protected function loadConfig($force) {
		if (!$force && isset($_SESSION['sysconfig']))
			return $this->cfg = $_SESSION['sysconfig'];

		$this->cfg = $this->fetchConfig();
		$_SESSION['sysconfig'] = $this->cfg;
	}

	protected function fetchConfig() {
		$cfg = array();

		$options = $this->api->system_config->index();

		foreach ($options as $opt) {
			if (!array_key_exists($opt->category, $cfg))
				$cfg[$opt->category] = array();

			$cfg[$opt->category][$opt->name] = $opt->attributes();
		}

		return $cfg;
	}

	protected function setupIterator() {
		$this->categories = new ArrayObject($this->cfg);
		$this->catIterator = $this->categories->getIterator();

		$this->options = new ArrayObject($this->catIterator->current());
		$this->optIterator = $this->options->getIterator();
	}

	/* Iterator methods */
	public function current() {
		return $this->optIterator->current()->value;
	}

	public function key() {
		return $this->catIterator->key().':'.$this->optIterator->key();
	}

	public function next() {
		$this->optIterator->next();

		if (!$this->optIterator->valid()) {
			$this->catIterator->next();

			if (!$this->catIterator->valid())
				return;

			$this->options = new ArrayObject($this->catIterator->current());
			$this->optIterator = $this->options->getIterator();
		}
	}

	public function rewind() {
		$this->setupIterator();
	}

	public function valid() {
		return $this->catIterator->valid() && $this->optIterator->valid();
	}
}
