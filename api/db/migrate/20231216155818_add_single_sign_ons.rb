class AddSingleSignOns < ActiveRecord::Migration[7.0]
  def change
    create_table :single_sign_ons do |t|
      t.references  :user,                          null: false
      t.references  :token,                         null: true
      t.timestamps
    end

    add_column :oauth2_clients, :allow_single_sign_on, :boolean, null: false, default: true
    add_column :oauth2_authorizations, :single_sign_on_id, :integer, null: true
    add_index :oauth2_authorizations, :single_sign_on_id
  end
end
