<?php

// Regression test for XTemplate table column tracking. Header columns must not
// be counted together with the first body row when pagination computes colspan.

require __DIR__ . '/../../../webui/lib/xtemplate.lib.php';

class PaginationDouble
{
    public function pageLinks($count)
    {
        return [
            (object) [
                'pageNumber' => 1,
                'path' => '?curpage=0',
                'isCurrent' => true,
            ],
            (object) [
                'pageNumber' => 2,
                'path' => '?curpage=1',
                'isCurrent' => false,
            ],
        ];
    }

    public function hasNextPage()
    {
        return false;
    }

    public function linkAt($index)
    {
        return $this->pageLinks(7)[$index];
    }

    public function nextPageLink()
    {
        return (object) ['path' => '?curpage=1'];
    }
}

function assert_matches($pattern, $actual, $message)
{
    if (!preg_match($pattern, $actual)) {
        fwrite(STDERR, $message . "\nPattern: " . $pattern . "\nIn: " . $actual . "\n");
        exit(1);
    }
}

function assert_not_matches($pattern, $actual, $message)
{
    if (preg_match($pattern, $actual)) {
        fwrite(STDERR, $message . "\nPattern: " . $pattern . "\nIn: " . $actual . "\n");
        exit(1);
    }
}

$xtpl = new XTemplate(__DIR__ . '/../../../webui/template/template.html');

foreach (['A', 'B', 'C'] as $heading) {
    $xtpl->table_add_category($heading);
}

foreach (['a', 'b', 'c'] as $value) {
    $xtpl->table_td($value);
}

$xtpl->table_tr();
$xtpl->table_pagination(new PaginationDouble());
$xtpl->table_out('generic-pagination-test');

$html = $xtpl->text('main.table');

assert_matches(
    '/class="pagination-row"[^>]*>.*colspan="3"/s',
    $html,
    'Pagination colspan should match the three table columns.'
);
assert_not_matches(
    '/class="pagination-row"[^>]*>.*colspan="6"/s',
    $html,
    'Pagination colspan should not include both header and body columns.'
);

echo "XTemplate table pagination colspan matches table columns.\n";
