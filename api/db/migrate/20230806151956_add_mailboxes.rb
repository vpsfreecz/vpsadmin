class AddMailboxes < ActiveRecord::Migration[7.0]
  def change
    create_table :mailboxes do |t|
      t.string      :label,                       null: false, limit: 255
      t.string      :server,                      null: false, limit: 255
      t.integer     :port,                        null: false, default: 995
      t.string      :user,                        null: false, limit: 255
      t.string      :password,                    null: false, limit: 255
      t.boolean     :enable_ssl,                  null: false, default: true
      t.timestamps                                null: false
    end

    create_table :mailbox_handlers do |t|
      t.references  :mailbox,                     null: false
      t.string      :class_name,                  null: false
      t.integer     :order,                       null: false, default: 1
      t.boolean     :continue,                    null: false, default: false
      t.timestamps                                null: false
    end
  end
end
