<?php

class Pagination
{
    private $resourceList;
    private $baseUrl;
    private $limit;
    private $history;

    /**
     * @param \HaveAPI\Client\ResourceInstanceList $resourceList
     * @param \HaveAPI\Client\Action $action
     */
    public function __construct($resourceList, $action = null)
    {
        if (is_null($resourceList) && is_null($action)) {
            throw new Exception('Provide either resourceList or action');
        }

        $this->resourceList = $resourceList;

        if (is_null($action)) {
            $action = $resourceList->getAction();
        }

        $input = $action->getParameters('input');

        $this->baseUrl = $_SERVER['PATH_INFO'];
        $this->limit = isset($_GET['limit']) ? $_GET['limit'] : $input->limit->default;
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
        return $this->resourceList->count() >= $this->limit && $this->limit > 0;
    }

    /**
     * @return string
     */
    public function nextPageUrl()
    {
        $history = $this->history;
        $history[] = [
            'from_id' => $_GET['from_id'] ?? 0,
            'limit' => $_GET['limit'] ?? $this->limit,
        ];

        $params = array_merge(
            $_GET,
            ['from_id' =>  $this->resourceList->last()->id],
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
                'from_id' => $lastItem['from_id'],
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
                'from_id' => $lastItem['from_id'],
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

        if (isset($_GET['from_id'])) {
            $ret['from_id'] = $_GET['from_id'];
        }

        $history = $this->history;
        $history[] = [
            'from_id' => $_GET['from_id'] ?? 0,
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
            list($from_id, $limit) = explode(':', $v);

            $ret[] = [
                'from_id' => $from_id,
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
            $entries[] = $item['from_id'] . ':' . $item['limit'];
        }

        return ['pagination' => implode(',', $entries)];
    }
}