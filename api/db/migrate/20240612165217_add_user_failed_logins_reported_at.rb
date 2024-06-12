class AddUserFailedLoginsReportedAt < ActiveRecord::Migration[7.1]
  class UserFailedLogin < ActiveRecord::Base; end

  def change
    add_column :user_failed_logins, :reported_at, :datetime, null: true

    reversible do |dir|
      dir.up do
        UserFailedLogin.all.update_all(reported_at: Time.now)
      end
    end
  end
end
