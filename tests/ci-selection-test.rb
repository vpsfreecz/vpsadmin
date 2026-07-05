#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for tools/select_ci_tests.rb and tests/ci-selection.yml. Add cases
# here when selection rules gain new precedence or fallback behavior.

require 'minitest/autorun'
require_relative '../tools/select_ci_tests'

class CiTestSelectionTest < Minitest::Test
  def selector
    @selector ||= CiTestSelector.new
  end

  def test_no_changed_files_skips
    selection = selector.select([])

    assert_equal 'skip', selection.mode
    assert_empty selection.filter
  end

  def test_skip_only_changes_skip_integration_ci
    selection = selector.select(['tests/README.md'])

    assert_equal 'skip', selection.mode
  end

  def test_migration_spec_harness_changes_skip_integration_ci
    selection = selector.select([
                                  '.git-hooks/pre_commit/migration_specs.rb',
                                  '.github/workflows/api-migration-specs.yml',
                                  '.github/workflows/api-specs.yml',
                                  '.overcommit.yml',
                                  'api/spec/migration_helper.rb',
                                  'api/spec/migrations/20260703120000_add_czech_language_spec.rb',
                                  'tools/check_migration_specs.rb'
                                ])

    assert_equal 'skip', selection.mode
  end

  def test_mixed_skip_and_runtime_changes_select_runtime_tags
    selection = selector.select(['tests/README.md', 'webui/pages/page_login.php'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui-auth'
    assert_match(/tag=ci && /, selection.filter)
  end

  def test_full_rule_wins
    selection = selector.select(['flake.lock'])

    assert_equal 'full', selection.mode
    assert_equal 'tag=ci', selection.filter
  end

  def test_unknown_runtime_path_falls_back_to_full
    selection = selector.select(['api/lib/vpsadmin/api/new_shared_runtime.rb'])

    assert_equal 'full', selection.mode
    assert_match(/unmapped runtime paths/, selection.reason)
  end

  def test_webui_spec_selects_matching_script
    selection = selector.select(['tests/playwright/webui/specs/transactions.spec.cjs'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui-transactions'
    refute_includes selection.tags, 'webui-auth'
  end

  def test_security_advisory_webui_spec_selects_dedicated_script
    selection = selector.select(['tests/playwright/webui/specs/security-advisories.spec.cjs'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui-security-advisories'
    assert_includes selection.tags, 'alerts'
    assert_includes selection.tags, 'support'
  end

  def test_security_advisory_api_path_selects_browser_coverage
    selection = selector.select(['api/models/security_advisory.rb'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui-security-advisories'
    assert_includes selection.tags, 'webui-support-pages'
    assert_includes selection.tags, 'alerts'
  end

  def test_shared_webui_file_selects_all_webui_scripts
    selection = selector.select(['tests/playwright/webui/lib/pages/vps.cjs'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui'
  end

  def test_public_webui_asset_selects_all_webui_scripts
    selection = selector.select(['webui/public/js/transaction-chains.js'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui'
  end

  def test_public_webui_entrypoint_selects_all_webui_scripts
    selection = selector.select(['webui/public/index.php'])

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'webui'
  end

  def test_webui_phpunit_tests_skip_integration_ci
    selection = selector.select(['webui/tests/Regression/XTemplateTablePaginationTest.php'])

    assert_equal 'skip', selection.mode
  end

  def test_webui_phpunit_config_skips_integration_ci
    selection = selector.select(['webui/phpunit.xml.dist'])

    assert_equal 'skip', selection.mode
  end

  def test_webui_phpunit_workflow_skips_integration_ci
    selection = selector.select(['.github/workflows/webui-phpunit.yml'])

    assert_equal 'skip', selection.mode
  end

  def test_multi_area_selection_builds_single_or_expression
    selection = selector.select(
      [
        'api/models/transaction_chains/vps/migrate.rb',
        'api/models/transaction_chains/dataset/backup.rb'
      ]
    )

    assert_equal 'selected', selection.mode
    assert_includes selection.tags, 'vps-migrate'
    assert_includes selection.tags, 'storage-backup'
    assert_match(/tag=vps-migrate/, selection.filter)
    assert_match(/ \|\| /, selection.filter)
  end
end
