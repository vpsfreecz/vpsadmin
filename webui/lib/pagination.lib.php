<?php

class Pagination
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
            throw new Exception('Provide either resourceList or action');
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
            throw new Exception('Input parameter ' . $options['inputParameter'] . ' not found');
        }

        if (is_null($output->{$this->outputParameter})) {
            throw new Exception('Output parameter ' . $options['outputParameter'] . ' not found');
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
        $history[] = [
            $this->inputParameter => $_GET[$this->inputParameter] ?? 0,
            'limit' => $_GET['limit'] ?? $this->limit,
        ];

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
     * @return boolean
     */
    public function hasPreviousPage()
    {
        return count($this->history) > 0;
    }

    /**
     * @return string
     */
    public function previousPageUrl()
    {
        $history = $this->history;
        $lastItem = array_pop($history);

        $params = array_merge(
            $_GET,
            [
                $this->inputParameter => $lastItem[$this->inputParameter],
                'limit' => $lastItem['limit'],
            ],
            $this->appendHistory($history),
        );

        return $this->baseUrl . '?' . http_build_query($params);
    }

    /**
     * return boolean
     */
    public function hasFirstPage()
    {
        return count($this->history) > 1;
    }

    /**
     * @return string
     */
    public function firstPageUrl()
    {
        $history = $this->history;
        $lastItem = $history[0];

        $params = array_merge(
            $_GET,
            [
                $this->inputParameter => $lastItem[$this->inputParameter],
                'limit' => $lastItem['limit'],
            ],
            $this->appendHistory([]),
        );

        return $this->baseUrl . '?' . http_build_query($params);
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
        $history[] = [
            $this->inputParameter => $_GET[$this->inputParameter] ?? 0,
            'limit' => $_GET['limit'] ?? $this->limit,
        ];

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
            [$parameter, $limit] = explode(':', $v);

            $ret[] = [
                $this->inputParameter => $parameter,
                'limit' => $limit,
            ];
        }

        return $ret;
    }

    protected function appendHistory($history)
    {
        if (count($history) == 0) {
            return ['pagination' => ''];
        }

        $entries = [];

        foreach ($history as $item) {
            $entries[] = $item[$this->inputParameter] . ':' . $item['limit'];
        }

        return ['pagination' => implode(',', $entries)];
    }
}
