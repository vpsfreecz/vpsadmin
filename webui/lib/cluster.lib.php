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

    public function getOption($cat, $name)
    {
        return $this->cfg[$cat][$name];
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

/** Validate runtime metadata independently of deployment-specific choice values. */
function system_config_choices(array $option): ?array
{
    $choices = $option['choices'] ?? null;
    $nullable = $option['value_nullable'] ?? null;

    if ($choices === null && $nullable === null) {
        return null;
    }

    if (!is_array($choices) || !$choices || !is_bool($nullable)
        || !in_array($option['type'], ['String', 'Integer'], true)) {
        throw new UnexpectedValueException('Invalid configuration choices');
    }

    $values = [];

    foreach ($choices as $choice) {
        $choice = is_object($choice) ? get_object_vars($choice) : $choice;

        if (!is_array($choice) || !array_key_exists('value', $choice)
            || !isset($choice['label']) || !is_string($choice['label']) || trim($choice['label']) === ''
            || ($option['type'] === 'String' && !is_string($choice['value']))
            || ($option['type'] === 'Integer' && (!is_int($choice['value']) || abs($choice['value']) > 9007199254740991))) {
            throw new UnexpectedValueException('Invalid configuration choices');
        }

        $token = json_encode($choice['value'], JSON_THROW_ON_ERROR);

        if (array_key_exists($token, $values)) {
            throw new UnexpectedValueException('Invalid configuration choices');
        }

        $values[$token] = $choice['label'];
    }

    if ($nullable) {
        $values['null'] = _('Unset');
    }

    return $values;
}

function system_config_choice_html(string $name, array $choices, $value): string
{
    $current = json_encode($value, JSON_THROW_ON_ERROR | JSON_PRESERVE_ZERO_FRACTION);
    $html = '<select name="sysconfig_choices[' . h($name) . ']">';

    if (!array_key_exists($current, $choices)) {
        $html .= '<option selected disabled value="' . h($current) . '">'
            . h(_('Unsupported current value') . ': ' . $current) . '</option>';
    }

    foreach ($choices as $token => $label) {
        $html .= '<option value="' . h((string) $token) . '"'
            . ($current === (string) $token ? ' selected' : '') . '>' . h($label) . '</option>';
    }

    return $html . '</select>';
}

/** Resolve one explicit route target; posted setting fields never choose a row. */
function system_config_target(array $query): ?array
{
    foreach (['category', 'name'] as $field) {
        if (!isset($query[$field]) || !is_string($query[$field])
            || !preg_match('/\A[A-Za-z0-9_]{1,75}\z/', $query[$field])) {
            return null;
        }
    }

    return [$query['category'], $query['name']];
}

/** Decode the selected row using the existing ordinary and marked-choice paths. */
function system_config_changes(array $option, array $post): array
{
    $category = $option['category'];
    $name = $option['name'];
    $key = $category . ':' . $name;
    $current = $option['value'];
    $changes = [];
    $failed = [];
    $submittedChoices = $post['sysconfig_choices'] ?? [];

    try {
        $choices = system_config_choices($option);

        if (is_array($submittedChoices) && array_key_exists($key, $submittedChoices)) {
            if (!is_string($submittedChoices[$key])) {
                throw new UnexpectedValueException('Invalid choice token');
            }

            $value = json_decode($submittedChoices[$key], true, 512, JSON_THROW_ON_ERROR);

            if (!is_string($value) && !is_int($value) && $value !== null) {
                throw new UnexpectedValueException('Invalid choice value');
            }

            if ($value === $current) {
                return [$changes, $failed];
            }

            $token = json_encode($value, JSON_THROW_ON_ERROR);

            if ($choices !== null && !array_key_exists($token, $choices)) {
                throw new UnexpectedValueException('Unsupported choice value');
            }

            $changes[] = [$category, $name, $value, true];
            return [$changes, $failed];
        }

        // A choice select with an unsupported disabled current option submits
        // no value. Do not turn an absent field into a write.
        if ($choices !== null && !array_key_exists($key, $post)) {
            return [$changes, $failed];
        }

        if ($option['type'] === 'Boolean') {
            $value = !empty($post[$key]);

            if ((bool) $current !== $value) {
                $changes[] = [$category, $name, $value ? '1' : '0', false];
            }

        } elseif (array_key_exists($key, $post) && $post[$key] != $current) {
            $changes[] = [$category, $name, $post[$key], false];
        }

    } catch (UnexpectedValueException|JsonException $e) {
        $failed[] = $key;
    }

    return [$changes, $failed];
}

function system_config_update($api, string $category, string $name, $value, bool $choice)
{
    if (!$choice || !is_string($value) || trim($value) !== '') {
        return $api->system_config->update($category, $name, ['value' => $value]);
    }

    // The dynamic client normalizes nullable blank Strings to null. Only this
    // known non-null choice needs a local descriptor; cached metadata stays intact.
    $action = $api->system_config->update;
    $description = clone $action->getResource()->getDescription()->actions->{$action->name()};
    $description->input = clone $description->input;
    $description->input->parameters = clone $description->input->parameters;
    $description->input->parameters->value = clone $description->input->parameters->value;
    $description->input->parameters->value->nullable = false;
    $exactAction = new \HaveAPI\Client\Action(
        $action->getClient(),
        $action->getResource(),
        $action->name(),
        $description,
        []
    );

    return $exactAction->call($category, $name, ['value' => $value]);
}
