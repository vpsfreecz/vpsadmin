<?php

use PHPUnit\Framework\TestCase;

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

final class XTemplateTablePaginationTest extends TestCase
{
    public function testPaginationColspanMatchesTableColumns(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/xtemplate.lib.php';

        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');

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

        self::assertMatchesRegularExpression('/class="pagination-row"[^>]*>.*colspan="3"/s', $html);
        self::assertDoesNotMatchRegularExpression('/class="pagination-row"[^>]*>.*colspan="6"/s', $html);
    }
}
