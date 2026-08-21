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
        self::assertStringContainsString("isAdmin() && (\$change->user_session ?? null)", $source);
        self::assertStringContainsString('$change->user_session_owned_by_user', $source);
        self::assertStringNotContainsString("\$change->source === 'authenticated'", $source);
        self::assertStringContainsString('h($u->login)', $source);
    }
}
