# frozen_string_literal: true

RSpec.describe 'core database schema' do # rubocop:disable RSpec/DescribeClass
  def api_root
    File.expand_path('../..', __dir__)
  end

  def repo_root
    File.expand_path('..', api_root)
  end

  def schema_source
    File.read(File.join(api_root, 'db/schema.rb'))
  end

  def schema_tables
    schema_source.scan(/create_table "([^"]+)"/).flatten.sort
  end

  def latest_core_migration_version
    Dir[File.join(api_root, 'db/migrate/*.rb')].filter_map do |path|
      File.basename(path)[/\A(\d+)/, 1]
    end.max
  end

  def schema_version
    schema_source[/define\(version:\s*([0-9_]+)/, 1]&.delete('_')
  end

  def plugin_migration_sources
    Dir[File.join(repo_root, 'plugins/*/api/db/migrate/*.rb')]
  end

  def create_table_names(source)
    source.scan(/create_table\s*(?:\(\s*)?(?::([a-zA-Z_]\w*)|["']([^"']+)["'])/).map do |symbol, string|
      symbol || string
    end
  end

  def create_join_table_names(source)
    source.scan(
      /create_join_table\s*(?:\(\s*)?(?::([a-zA-Z_]\w*)|["']([^"']+)["'])\s*,\s*(?::([a-zA-Z_]\w*)|["']([^"']+)["'])/
    ).map do |left_symbol, left_string, right_symbol, right_string|
      [left_symbol || left_string, right_symbol || right_string].sort.join('_')
    end
  end

  def plugin_table_names
    plugin_migration_sources.flat_map do |path|
      source = File.read(path)
      create_table_names(source) + create_join_table_names(source)
    end.uniq.sort
  end

  it 'does not contain tables created by plugin migrations' do
    leaked_tables = schema_tables & plugin_table_names

    expect(leaked_tables).to be_empty,
                             "Plugin tables leaked into api/db/schema.rb: #{leaked_tables.join(', ')}. " \
                             'Dump core schema with VPSADMIN_PLUGINS=none.'
  end

  it 'uses the latest core migration version' do
    expect(schema_version).to eq(latest_core_migration_version)
  end
end
