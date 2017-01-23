class Setup < ActiveRecord::Migration
  def change
    create_table :user_requests do |t|
      t.references  :user,                null: true
      t.string      :type,                null: false, limit: 255
      t.integer     :state,               null: false, default: 0
      t.string      :ip_addr,             null: false, limit: 127
      t.string      :ip_addr_ptr,         null: false
      t.integer     :last_mail_id,        null: false, default: 0
      t.references  :admin,               null: true
      t.string      :admin_response,      null: true,  limit: 500
      t.timestamps

      # Registration fields
      t.string      :login
      t.string      :full_name
      t.string      :org_name
      t.string      :org_id
      t.string      :email
      t.text        :address
      t.integer     :year_of_birth
      t.string      :how
      t.string      :note
      t.references  :os_template
      t.references  :location
      t.string      :currency
      t.references  :language

      # Change request fields
      # full_name
      # email
      # address
      t.string      :change_reason,       null: true,  limit: 255
    end

    add_index :user_requests, :user_id
    add_index :user_requests, :type
    add_index :user_requests, :state
    add_index :user_requests, :admin_id
  end
end
