class AddOauth2AuthorizationsUserAgent < ActiveRecord::Migration[7.1]
  class Oauth2Authorization < ::ActiveRecord::Base
    belongs_to :user_device
  end

  class UserDevice < ::ActiveRecord::Base
    has_many :oauth2_authorizations
  end

  def change
    add_column :oauth2_authorizations, :user_agent_id, :bigint, null: true

    reversible do |dir|
      dir.up do
        Oauth2Authorization.all.each do |auth|
          next if auth.user_device.nil?

          auth.update!(user_agent_id: auth.user_device.user_agent_id)
        end
      end
    end
  end
end
