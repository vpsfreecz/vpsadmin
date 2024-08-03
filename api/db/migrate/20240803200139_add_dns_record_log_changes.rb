class AddDnsRecordLogChanges < ActiveRecord::Migration[7.1]
  class DnsRecordLog < ActiveRecord::Base
    serialize :attr_changes, coder: JSON
  end

  def change
    add_column :dns_record_logs, :attr_changes, :text, null: true, limit: 65_536

    reversible do |dir|
      dir.up do
        DnsRecordLog.all.each do |log|
          log.update!(attr_changes: { content: log.content })
        end
      end

      dir.down do
        DnsRecordLog.all.each do |log|
          log.update!(content: log.attr_changes['content'] || '')
        end
      end
    end

    remove_column :dns_record_logs, :content, null: false, limit: 64_000
    change_column_null :dns_record_logs, :attr_changes, false
  end
end
