class MakeOomReportTaskUidsUnsigned < ActiveRecord::Migration[8.1]
  SIGNED_INTEGER_MAX = (2**31) - 1

  def change
    reversible do |dir|
      dir.up do
        validate_uids!('host_uid < 0 OR vps_uid < 0', 'negative')
        change_uids(unsigned: true)
      end

      dir.down do
        validate_uids!(
          "host_uid > #{SIGNED_INTEGER_MAX} OR vps_uid > #{SIGNED_INTEGER_MAX}",
          'outside the signed 32-bit range',
          error_class: ActiveRecord::IrreversibleMigration
        )
        change_uids(unsigned: false)
      end
    end
  end

  protected

  def validate_uids!(condition, description, error_class: ActiveRecord::MigrationError)
    invalid_id = connection.select_value(<<~SQL.squish)
      SELECT id
      FROM oom_report_tasks
      WHERE #{condition}
      LIMIT 1
    SQL
    return if invalid_id.nil?

    raise error_class,
          "oom_report_tasks row ##{invalid_id} contains a #{description} host_uid or vps_uid"
  end

  def change_uids(unsigned:)
    change_table :oom_report_tasks, bulk: true do |t|
      t.change :host_uid, :integer, null: false, unsigned: unsigned
      t.change :vps_uid, :integer, null: true, unsigned: unsigned
    end
  end
end
