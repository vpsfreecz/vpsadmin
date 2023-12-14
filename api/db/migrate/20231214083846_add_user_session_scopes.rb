class AddUserSessionScopes < ActiveRecord::Migration[7.0]
  def change
    add_column :user_sessions, :scope, :text, null: false, limit: 65535, default: '["all"]'

    reversible do |dir|
      dir.up do
        change_column :oauth2_authorizations, :scope, :text, limit: 65535, null: false
      end

      dir.down do
        change_column :oauth2_authorizations, :scope, :string, limit: 255, null: true
      end
    end
  end
end
