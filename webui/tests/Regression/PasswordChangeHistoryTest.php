<?php

use PHPUnit\Framework\TestCase;

final class PasswordChangeHistoryTest extends TestCase
{
    public function testProfileSidebarLinksToPasswordChangeHistory(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_adminm.php');

        self::assertStringContainsString("'member.password-changes'", $source);
        self::assertStringContainsString('action=password_changes', $source);
        self::assertStringContainsString("case 'password_changes':", $source);
        self::assertStringContainsString("list_password_changes(\$_GET['id']);", $source);
    }

    public function testHistoryUsesApiLabelsAndProtectsSessionDetails(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/users.forms.php');

        self::assertStringContainsString(
            'api_param_choice_label($output->source, $change->source)',
            $source
        );
        self::assertStringContainsString(
            "'includes' => 'user_session,user_session__user'",
            $source
        );
        self::assertStringContainsString('if ($change->user_session_id)', $source);
        self::assertStringContainsString('$sessionResource = $change->user_session', $source);
        self::assertStringContainsString('$change->user_session_owned_by_user', $source);
        self::assertStringContainsString("\$change->source === 'administrator'", $source);
        self::assertStringContainsString(
            '$sessionUser = $sessionResource ? $sessionResource->user : null',
            $source
        );
        self::assertStringContainsString("\$xtpl->table_add_category(_('Admin'))", $source);
        self::assertStringContainsString("_('IP address')", $source);
        self::assertStringContainsString("_('IP PTR')", $source);
        self::assertStringContainsString("_('User agent')", $source);
        self::assertStringContainsString('$changeAttributes = $change->attributes()', $source);
        self::assertStringContainsString("'inline password-change-client-details'", $source);
        self::assertStringContainsString("table_out('password-change-history')", $source);
        self::assertStringContainsString('h($u->login)', $source);
        self::assertStringContainsString('h($sessionUser->login)', $source);
    }
}
