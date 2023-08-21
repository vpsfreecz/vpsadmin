class ChangeMailboxesDefaultPortToImap < ActiveRecord::Migration[7.0]
  def change
    change_column_default(:mailboxes, :port, from: 995, to: 993)
  end
end
