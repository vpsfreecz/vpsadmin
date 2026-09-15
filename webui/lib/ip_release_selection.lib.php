<?php

// A preview belongs to one authenticated account and browser session. Store the
// explicit candidate snapshot so pagination never expands a selection silently.
final class IpReleaseSelection
{
    public const PAGE_SIZE = 500;

    public static function create(array $rows, array $filters, int $owner): array
    {
        return ['owner' => $owner, 'rows' => $rows, 'filters' => $filters,
            'selected' => array_fill_keys(array_column($rows, 'id'), true), 'settings' => []];
    }

    public static function page(array $state, int $page): array
    {
        return array_slice($state['rows'], max(0, $page) * self::PAGE_SIZE, self::PAGE_SIZE);
    }

    public static function update(array &$state, int $owner, int $page, array $selected, string $operation = 'page'): void
    {
        if ($state['owner'] !== $owner || $page < 0 || $page > max(0, (int) ceil(count($state['rows']) / self::PAGE_SIZE) - 1)) {
            throw new InvalidArgumentException(_('Invalid address selection.'));
        }
        $pageIds = array_column(self::page($state, $page), 'id');
        foreach ($selected as $id) {
            if (!is_string($id) || !ctype_digit($id) || !in_array((int) $id, $pageIds, true)) {
                throw new InvalidArgumentException(_('Invalid address selection.'));
            }
        }
        foreach ($pageIds as $id) {
            unset($state['selected'][$id]);
        }
        foreach ($selected as $id) {
            $state['selected'][(int) $id] = true;
        }
        if ($operation === 'all') {
            $state['selected'] = array_fill_keys(array_column($state['rows'], 'id'), true);
        } elseif ($operation === 'none') {
            $state['selected'] = [];
        }
    }
}
