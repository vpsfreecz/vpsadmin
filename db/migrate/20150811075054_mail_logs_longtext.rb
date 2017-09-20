class MailLogsLongtext < ActiveRecord::Migration
  def up
    # longtext
    change_column :mail_logs, :text_plain, :text, :limit => 4294967295
    change_column :mail_logs, :text_html, :text, :limit => 4294967295
  end

  def down
    # text
    change_column :mail_logs, :text_plain, :text, :limit => 65535
    change_column :mail_logs, :text_html, :text, :limit => 65535
  end
end
