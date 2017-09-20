class MailRecipientVoluntaryTo < ActiveRecord::Migration
  def change
    change_column_null :mail_recipients, :to, true
  end
end
