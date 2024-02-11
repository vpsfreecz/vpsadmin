class MailLogsLongtext < ActiveRecord::Migration
  def up
    # longtext
    change_column :mail_logs, :text_plain, :text, limit: 4_294_967_295
    change_column :mail_logs, :text_html, :text, limit: 4_294_967_295
  end

  def down
    # text
    change_column :mail_logs, :text_plain, :text, limit: 65_535
    change_column :mail_logs, :text_html, :text, limit: 65_535
  end
end
