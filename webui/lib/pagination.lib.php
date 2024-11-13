<?php

namespace Pagination;

class Link
{
    public $number;
    public $path;

    public function __construct(int $pageNumber, string $path)
    {
        $this->number = $pageNumber;
        $this->path = $path;
    }
}

class Entry
{
    public $value;
    public $limit;

    public static function parse(string $string): Entry
    {
        [$value, $limit] = explode(':', $string);

        return new Entry($value, $limit);
    }

    public function __construct(int $value, int $limit)
    {
        $this->value = $value;
        $this->limit = $limit;
    }

    public function dump(): string
    {
        return $this->value . ':' . $this->limit;
    }
}

class History implements \ArrayAccess, \Countable, \Iterator
{
    private $position;
    private $array;

    public static function parse(string $string): History
    {
        $history = new History();

        if (trim($string) == '') {
            return $history;
        }

        $entries = explode(',', $string);

        foreach ($entries as $v) {
            $history[] = Entry::parse($v);
        }

        return $history;
    }

    public function __construct(array $array = [])
    {
        $this->position = 0;
        $this->array = $array;
    }

    public function pop(): Entry
    {
        return array_pop($this->array);
    }

    public function dump(): string
    {
        $entries = [];

        foreach ($this->array as $entry) {
            $entries[] = $entry->dump();
        }

        return implode(',', $entries);
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
        if (is_null($offset)) {
            $this->array[] = $value;
        } else {
            $this->array[$offset] = $value;
        }
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
    private $resourceList;
    private $baseUrl;
    private $limit;
    private $inputParameter;
    private $outputParameter;
    private $history;

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
    }

    public function setResourceList(mixed $resourceList): void
    {
        $this->resourceList = $resourceList;
    }

    public function hasNextPage(): bool
    {
        $count = is_array($this->resourceList) ? count($this->resourceList) : $this->resourceList->count();

        return $count == $this->limit && $this->limit > 0;
    }

    public function nextPageUrl(): string
    {
        $history = clone $this->history;
        $history[] = new Entry(
            $_GET[$this->inputParameter] ?? 0,
            $_GET['limit'] ?? $this->limit
        );

        if (is_array($this->resourceList)) {
            $last = $this->resourceList[ count($this->resourceList) - 1 ];
        } else {
            $last = $this->resourceList->last();
        }

        $params = array_merge(
            $_GET,
            [$this->inputParameter =>  $last->{$this->outputParameter}],
            $this->appendHistory($history),
        );

        return $this->baseUrl . '?' . http_build_query($params);
    }

    public function previousPageLinks(): array
    {
        $ret = [];
        $history = clone $this->history;
        $n = count($history);

        while(count($history) > 0) {
            $entry = $history->pop();

            $params = array_merge(
                $_GET,
                [
                    $this->inputParameter => $entry->value,
                    'limit' => $entry->limit,
                ],
                $this->appendHistory($history),
            );

            $url = $this->baseUrl . '?' . http_build_query($params);

            $ret[] = new Link($n--, $url);
        }

        return array_reverse($ret);
    }

    public function hiddenFormFields(): array
    {
        if (!isset($_GET['pagination'])) {
            return [];
        }

        $ret = [];

        if (isset($_GET[$this->inputParameter])) {
            $ret[$this->inputParameter] = $_GET[$this->inputParameter];
        }

        $history = clone $this->history;
        $history[] = new Entry(
            $_GET[$this->inputParameter] ?? 0,
            $_GET['limit'] ?? $this->limit
        );

        return array_merge($ret, $this->appendHistory($history));
    }

    protected function parseHistory(): History
    {
        return History::parse($_GET['pagination'] ?? '');
    }

    protected function appendHistory(History $history): array
    {
        if (count($history) == 0) {
            return ['pagination' => ''];
        }

        return ['pagination' => $history->dump()];
    }
}
