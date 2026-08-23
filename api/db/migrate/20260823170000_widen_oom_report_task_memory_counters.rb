class WidenOomReportTaskMemoryCounters < ActiveRecord::Migration[8.1]
  SIGNED_INTEGER_MAX = (2**31) - 1
  MEMORY_COLUMNS = {
    total_vm: { null: false },
    rss: { null: false },
    rss_anon: { null: true },
    rss_file: { null: true },
    rss_shmem: { null: true },
    pgtables_bytes: { null: false },
    swapents: { null: false }
  }.freeze

  def change
    reversible do |dir|
      dir.up do
        validate_memory_counters!('< 0', 'negative')
        change_memory_counters(:bigint, unsigned: true)
      end

      dir.down do
        validate_memory_counters!(
          "> #{SIGNED_INTEGER_MAX}",
          'outside the signed 32-bit range',
          error_class: ActiveRecord::IrreversibleMigration
        )
        change_memory_counters(:integer, unsigned: false)
      end
    end
  end

  protected

  def validate_memory_counters!(condition, description, error_class: ActiveRecord::MigrationError)
    invalid_id = connection.select_value(<<~SQL.squish)
      SELECT id
      FROM oom_report_tasks
      WHERE #{MEMORY_COLUMNS.keys.map { |column| "#{connection.quote_column_name(column)} #{condition}" }.join(' OR ')}
      LIMIT 1
    SQL
    return if invalid_id.nil?

    raise error_class,
          "oom_report_tasks row ##{invalid_id} contains a memory counter #{description}"
  end

  def change_memory_counters(type, unsigned:)
    change_table :oom_report_tasks, bulk: true do |t|
      MEMORY_COLUMNS.each do |column, options|
        t.change column, type, **options, unsigned:
      end
    end
  end
end
