<?php

use PHPUnit\Framework\TestCase;

class FormatErrorsResponse
{
    public function __construct(
        private string $message,
        private array $errors = []
    ) {}

    public function getMessage(): string
    {
        return $this->message;
    }

    public function getErrors(): array
    {
        return $this->errors;
    }
}

final class FormatErrorsTest extends TestCase
{
    public function testErrorMessageSeparatorIncludesSpace(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        self::assertStringStartsWith(
            'Error message: object not found',
            format_errors(new FormatErrorsResponse('object not found'))
        );
    }
}
