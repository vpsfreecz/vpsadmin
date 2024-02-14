<?php

class Munin {
    private $url;
    private $enabled;
    private $graphWidth;

    public function __construct($config) {
        $this->url = $config->get('webui', 'munin_url');
        $this->enabled = (bool) $this->url;
        $this->graphWidth = null;
    }

    public function isEnabled() {
        return $this->enabled;
    }

    public function linkPath($label, $path) {
        $ret = '';

        if ($this->isEnabled())
            $ret .= '<a href="'.$this->url.'/'.$path.'" target="_blank">';

        $ret .= $label;

        if ($this->isEnabled())
            $ret .= '</a>';

        return $ret;
    }

    public function linkHostPath($label, $fqdn, $path) {
        return $this->linkPath(
            $label,
            $this->getDomain($fqdn).'/'.$fqdn.'/'.$path
        );
    }

    public function linkHost($label, $fqdn) {
        return $this->linkPath(
            $label,
            $this->getDomain($fqdn).'/'.$fqdn
        );
    }

    public function hostGraphPath($fqdn, $type, $period) {
        return $this->url.'/'.$this->getDomain($fqdn).'/'.$fqdn.'/'.$type.'-'.$period.'.png';
    }

    public function linkHostGraphPath($fqdn, $type, $period, $dir = false) {
        $graph = $this->hostGraphPath($fqdn, $type, $period);

        $page = $this->url.'/'.$this->getDomain($fqdn).'/'.$fqdn.'/'.$type;

        if ($dir)
            $page .= '/index.html';
        else
            $page .= '.html';

        $ret = '<a href="'.$page.'" target="_blank">';
        $ret .= '<img src="'.$graph.'" alt="'.$fqdn.' - '.$type.'" '.($this->graphWidth ? 'width="'.$this->graphWidth.'"' : '').'>';
        $ret .= '</a>';

        return $ret;
    }

    public function setGraphWidth($width) {
        $this->graphWidth = $width;
    }

    private function getDomain($fqdn) {
        $names = explode('.', $fqdn);
        $domain = implode('.', array_slice($names, 1));

        return $domain;
    }
}
