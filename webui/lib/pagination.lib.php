<?php

namespace Pagination;

class Link
{
    public int $pageId;
    public int $pageNumber;
    public string $path;
    public bool $isCurrent;

    public function __construct(int $pageId, string $path, bool $isCurrent)
    {
        $this->pageId = $pageId;
        $this->pageNumber = $pageId + 1;
        $this->path = $path;
        $this->isCurrent = $isCurrent;
    }
}

class Entry
{
    public int $id;
    public int $value;

    public function __construct(int $id, int $value)
    {
        $this->id = $id;
        $this->value = $value;
    }

    public function dump(): string
    {
        return $this->value;
    }
}

class History implements \ArrayAccess, \Countable, \Iterator
{
    private $position;
    private $array;

    public static function parse(string $string, string $initialValue): History
    {
        $history = new History();

        if (trim($string) == '') {
            $history->addEntry((int) $initialValue);
            return $history;
        }

        $entries = explode('-', $string);

        foreach ($entries as $i => $v) {
            $history->addEntry((int) $v);
        }

        return $history;
    }

    public function __construct(array $array = [])
    {
        $this->position = 0;
        $this->array = $array;
    }

    public function dump(): string
    {
        $entries = [];

        foreach ($this->array as $entry) {
            $entries[] = $entry->dump();
        }

        return implode('-', $entries);
    }

    public function addEntry(int $value): Entry
    {
        $entry = new Entry(count($this->array), $value);
        $this->array[] = $entry;
        return $entry;
    }

    /* ArrayAccess methods */

    public function offsetExists(mixed $offset): bool
    {
        return isset($this->array[$offset]);
    }

    public function offsetGet(mixed $offset): mixed
    {
        return $this->array[$offset];
    }

    public function offsetSet(mixed $offset, mixed $value): void
    {
        throw new \Exception('offsetSet() is not supported');
    }

    public function offsetUnset(mixed $offset): void
    {
        unset($this->array[$offset]);
    }

    /* Countable methods */
    public function count(): int
    {
        return count($this->array);
    }

    /* Iterator methods */

    public function current(): mixed
    {
        return $this->array[$this->position];
    }

    public function key(): mixed
    {
        return $this->position;
    }

    public function next(): void
    {
        $this->position++;
    }

    public function rewind(): void
    {
        $this->position = 0;
    }

    public function valid(): bool
    {
        return isset($this->array[$this->position]);
    }
}

class System
{
    private mixed $resourceList;
    private string $baseUrl;
    private int $limit;
    private string $inputParameter;
    private string $outputParameter;
    private History $history;
    private int $currentPage;

    public function __construct(mixed $resourceList, \HaveAPI\Client\Action $action = null, array $options = [])
    {
        if (is_null($resourceList) && is_null($action)) {
            throw new \Exception('Provide either resourceList or action');
        }

        $this->resourceList = $resourceList;

        if (is_null($action)) {
            $action = $resourceList->getAction();
        }

        $input = $action->getParameters('input');
        $output = $action->getParameters('output');

        $this->inputParameter = $options['inputParameter'] ?? 'from_id';
        $this->outputParameter = $options['outputParameter'] ?? 'id';

        if (is_null($input->{$this->inputParameter})) {
            throw new \Exception('Input parameter ' . $this->inputParameter . ' not found');
        }

        if (is_null($output->{$this->outputParameter})) {
            throw new \Exception('Output parameter ' . $this->outputParameter . ' not found');
        }

        $this->baseUrl = $_SERVER['PATH_INFO'] ?? '';
        $this->limit = $_GET['limit'] ?? $options['defaultLimit'] ?? $input->limit->default ?? 25;
        $this->history = $this->parseHistory();
        $this->currentPage = (int) ($_GET['curpage'] ?? 0);
    }

    public function setResourceList(mixed $resourceList): void
    {
        $this->resourceList = $resourceList;
    }

    public function hasNextPage(): bool
    {
        $count = is_array($this->resourceList) ? count($this->resourceList) : $this->resourceList->count();

        return $this->currentPage < (count($this->history) - 1) || ($count == $this->limit && $this->limit > 0);
    }

    public function nextPageLink(): Link
    {
        if ($this->currentPage < (count($this->history) - 1) && isset($this->history[$this->currentPage + 1])) {
            $entry = $this->history[$this->currentPage + 1];

            $params = array_merge(
                $_GET,
                [
                    $this->inputParameter => $entry->value,
                    'curpage' => $this->currentPage + 1,
                ],
                $this->appendHistory($this->history),
            );

            return new Link(
                $entry->id,
                $this->baseUrl . '?' . http_build_query($params),
                false
            );
        }

        if (is_array($this->resourceList)) {
            $last = $this->resourceList[ count($this->resourceList) - 1 ];
        } else {
            $last = $this->resourceList->last();
        }

        $history = clone $this->history;
        $entry = $history->addEntry($last->{$this->outputParameter});

        $params = array_merge(
            $_GET,
            [
                $this->inputParameter => $last->{$this->outputParameter},
                'curpage' => $this->currentPage + 1,
            ],
            $this->appendHistory($history),
        );

        return new Link(
            $entry->id,
            $this->baseUrl . '?' . http_build_query($params),
            false
        );
    }

    public function pageLinks(int $maxLinks): array
    {
        $ret = [];
        $entries = $this->selectEntries($maxLinks);

        foreach ($entries as $entry) {
            $params = array_merge(
                $_GET,
                [
                    $this->inputParameter => $entry->value,
                    'curpage' => $entry->id,
                ],
                $this->appendHistory($this->history),
            );

            $url = $this->baseUrl . '?' . http_build_query($params);

            $ret[] = new Link($entry->id, $url, $entry->id == $this->currentPage);
        }

        return $ret;
    }

    public function currentPageId(): int
    {
        return $this->currentPage;
    }

    public function linkAt(int $id): Link
    {
        $entry = $this->history[$id];

        $params = array_merge(
            $_GET,
            [
                $this->inputParameter => $entry->value,
                'curpage' => $entry->id,
            ],
            $this->appendHistory($this->history),
        );

        $url = $this->baseUrl . '?' . http_build_query($params);

        return new Link($entry->id, $url, $entry->id == $this->currentPage);
    }

    protected function selectEntries(int $maxLinks): array
    {
        $entries = [];
        $i = 0;
        $countdown = null;

        foreach ($this->history as $entry) {
            array_push($entries, $entry);

            if (!is_null($countdown) && count($entries) > $maxLinks) {
                array_shift($entries);
            }

            if (!is_null($countdown) && --$countdown <= 0) {
                break;
            }

            if (is_null($countdown) && $i++ == $this->currentPage) {
                $countdown = max($maxLinks - count($entries), floor($maxLinks / 2));
            }
        }

        if (is_null($countdown) || count($entries) > $maxLinks) {
            while (count($entries) > $maxLinks) {
                array_shift($entries);
            }
        }

        return $entries;
    }

    protected function parseHistory(): History
    {
        return History::parse($_GET['pagination'] ?? '', $_GET[$this->inputParameter] ?? '0');
    }

    protected function appendHistory(History $history): array
    {
        if (count($history) == 0) {
            return ['pagination' => ''];
        }

        return ['pagination' => $history->dump()];
    }
}
