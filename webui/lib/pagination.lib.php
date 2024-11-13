<?php

namespace Pagination;

class Entry
{
    public $value;
    public $limit;

    public static function parse($string)
    {
        [$value, $limit] = explode(':', $string);

        return new Entry($value, $limit);
    }

    public function __construct($value, $limit)
    {
        $this->value = $value;
        $this->limit = $limit;
    }

    public function dump()
    {
        return $this->value . ':' . $this->limit;
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

    /**
     * @param \HaveAPI\Client\ResourceInstanceList $resourceList
     * @param \HaveAPI\Client\Action $action
     */
    public function __construct($resourceList, $action = null, $options = [])
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

    /**
     * @param \HaveAPI\Client\ResourceInstanceList $resourceList
     */
    public function setResourceList($resourceList)
    {
        $this->resourceList = $resourceList;
    }

    /**
     * @return boolean
     */
    public function hasNextPage()
    {
        $count = is_array($this->resourceList) ? count($this->resourceList) : $this->resourceList->count();

        return $count == $this->limit && $this->limit > 0;
    }

    /**
     * @return string
     */
    public function nextPageUrl()
    {
        $history = $this->history;
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

    /**
     * @return array list of previous pages
     */
    public function previousPageUrls()
    {
        $ret = [];
        $history = $this->history;
        $n = count($history);

        while(count($history) > 0) {
            $entry = array_pop($history);

            $params = array_merge(
                $_GET,
                [
                    $this->inputParameter => $entry->value,
                    'limit' => $entry->limit,
                ],
                $this->appendHistory($history),
            );

            $url = $this->baseUrl . '?' . http_build_query($params);

            $ret[] = [
                'page' => $n--,
                'url' => $url,
            ];
        }

        return array_reverse($ret);
    }

    /**
     * @return array
     */
    public function hiddenFormFields()
    {
        if (!isset($_GET['pagination'])) {
            return [];
        }

        $ret = [];

        if (isset($_GET[$this->inputParameter])) {
            $ret[$this->inputParameter] = $_GET[$this->inputParameter];
        }

        $history = $this->history;
        $history[] = new Entry(
            $_GET[$this->inputParameter] ?? 0,
            $_GET['limit'] ?? $this->limit
        );

        return array_merge($ret, $this->appendHistory($history));
    }

    protected function parseHistory()
    {
        $ret = [];

        if (!isset($_GET['pagination']) || $_GET['pagination'] == '') {
            return $ret;
        }

        $entries = explode(',', $_GET['pagination']);

        foreach ($entries as $v) {
            $ret[] = Entry::parse($v);
        }

        return $ret;
    }

    protected function appendHistory($history)
    {
        if (count($history) == 0) {
            return ['pagination' => ''];
        }

        $entries = [];

        foreach ($history as $entry) {
            $entries[] = $entry->dump();
        }

        return ['pagination' => implode(',', $entries)];
    }
}
