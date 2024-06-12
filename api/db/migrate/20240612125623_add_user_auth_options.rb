class AddUserAuthOptions < ActiveRecord::Migration[7.1]
  class User < ActiveRecord::Base; end

  def change
    add_column :users, :enable_basic_auth, :boolean, null: false, default: false
    add_column :users, :enable_token_auth, :boolean, null: false, default: true
    add_column :users, :enable_oauth2_auth, :boolean, null: false, default: true

    reversible do |dir|
      dir.up do
        # Existing users will have HTTP basic authentication enabled, but
        # new accounts will have it disabled.
        User.all.update_all(enable_basic_auth: true)
      end
    end
  end
end
