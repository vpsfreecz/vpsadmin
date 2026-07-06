# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'bundler/setup'
require 'rspec'
require 'active_record'
require 'active_support/all'

require_relative 'support/db_setup'

module MigrationSpecSupport
  DB_SUFFIX = 'migration'

  module_function

  def migration_path(name)
    File.expand_path("../db/migrate/#{name}.rb", __dir__)
  end

  def require_migration(name)
    path = migration_path(name)
    raise "Migration #{name.inspect} not found at #{path}" unless File.exist?(path)

    require path
  end

  def plugin_migration_path(plugin, name)
    File.expand_path("../../plugins/#{plugin}/api/db/migrate/#{name}.rb", __dir__)
  end

  def require_plugin_migration(plugin, name)
    path = plugin_migration_path(plugin, name)
    raise "Plugin migration #{plugin}/#{name.inspect} not found at #{path}" unless File.exist?(path)

    require path
  end
end

module MigrationSpecHelpers
  def connection
    ActiveRecord::Base.connection
  end

  def reset_database!
    connection.disable_referential_integrity do
      connection.tables.each do |table|
        connection.drop_table(table, force: :cascade)
      end
    end
  end

  def define_schema(&)
    ActiveRecord::Schema.define(version: 0, &)
  end

  def migrate_up!(migration_class = described_class)
    migration_class.new.migrate(:up)
  end

  def migrate_down!(migration_class = described_class)
    migration_class.new.migrate(:down)
  end

  def table_exists?(table)
    connection.table_exists?(table)
  end

  def column_exists?(table, column)
    connection.column_exists?(table, column)
  end

  def column(table, column)
    connection.columns(table).find { |v| v.name == column.to_s }
  end

  def index_exists?(table, columns_or_name)
    if columns_or_name.is_a?(Symbol) || columns_or_name.is_a?(String)
      connection.indexes(table).any? { |idx| idx.name == columns_or_name.to_s }
    else
      connection.index_exists?(table, columns_or_name)
    end
  end

  def insert_row(table, attrs)
    columns = attrs.keys.map { |name| connection.quote_column_name(name) }.join(', ')
    values = attrs.values.map { |value| connection.quote(value) }.join(', ')

    connection.execute(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name(table)} (#{columns})
      VALUES (#{values})
    SQL

    connection.select_value('SELECT LAST_INSERT_ID()').to_i
  end

  def rows(table, order: :id)
    sql = "SELECT * FROM #{connection.quote_table_name(table)}"
    sql << " ORDER BY #{Array(order).map { |v| connection.quote_column_name(v) }.join(', ')}" if order

    connection.select_all(sql).to_a
  end

  def find_rows(table, where = {}, order: :id)
    clauses = where.map do |column_name, value|
      "#{connection.quote_column_name(column_name)} = #{connection.quote(value)}"
    end
    sql = "SELECT * FROM #{connection.quote_table_name(table)}"
    sql << " WHERE #{clauses.join(' AND ')}" if clauses.any?
    sql << " ORDER BY #{Array(order).map { |v| connection.quote_column_name(v) }.join(', ')}" if order

    connection.select_all(sql).to_a
  end

  def find_row(table, where = {})
    found = find_rows(table, where, order: false)
    expect(found.length).to eq(1), "expected one #{table} row matching #{where.inspect}, found #{found.length}"
    found.first
  end

  def row_count(table, where = {})
    clauses = where.map do |column_name, value|
      "#{connection.quote_column_name(column_name)} = #{connection.quote(value)}"
    end
    sql = "SELECT COUNT(*) FROM #{connection.quote_table_name(table)}"
    sql << " WHERE #{clauses.join(' AND ')}" if clauses.any?

    connection.select_value(sql).to_i
  end

  def boolish(value)
    value == true || value.to_s == '1'
  end

  def timestamp
    Time.utc(2026, 6, 15, 12, 0, 0)
  end
end

RSpec.configure do |config|
  config.include MigrationSpecHelpers

  config.before(:suite) do
    SpecDbSetup.establish_connection!(db_name_suffix: MigrationSpecSupport::DB_SUFFIX)
    SpecDbSetup.ensure_database_exists!
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Migration.verbose = false
  end

  config.before do
    reset_database!
  end
end
