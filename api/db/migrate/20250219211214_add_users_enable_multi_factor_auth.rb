class AddUsersEnableMultiFactorAuth < ActiveRecord::Migration[7.2]
  class User < ActiveRecord::Base
    has_many :user_totp_devices
    has_many :webauthn_credentials
  end

  class UserTotpDevice < ActiveRecord::Base
    belongs_to :user
  end

  class WebauthnCredential < ActiveRecord::Base
    belongs_to :user
  end

  def change
    add_column :users, :enable_multi_factor_auth, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        ::User.where('object_state < 3').each do |user|
          has_totp = user.user_totp_devices.where(enabled: true).any?
          has_webauthn = user.webauthn_credentials.where(enabled: true).any?
          next if !has_totp && !has_webauthn

          user.update!(enable_multi_factor_auth: true)
        end
      end
    end
  end
end
