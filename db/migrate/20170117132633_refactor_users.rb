class RefactorUsers < ActiveRecord::Migration
  def change
    rename_table :members, :users
    rename_column :users, :m_id, :id
    rename_column :users, :m_info, :info
    rename_column :users, :m_level, :level
    rename_column :users, :m_nick, :login
    rename_column :users, :m_name, :full_name
    rename_column :users, :m_pass, :password
    rename_column :users, :m_mail, :email
    rename_column :users, :m_address, :address
    rename_column :users, :m_monthly_payment, :monthly_payment
    rename_column :users, :m_mailer_enable, :mailer_enabled
    remove_column :users, :m_lang, :string, limit: 16

    add_index :users, :object_state
    add_index :users, :login, unique: true
  end
end
