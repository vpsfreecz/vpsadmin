class AddUserDevices < ActiveRecord::Migration[7.1]
  class Oauth2Authorization < ::ActiveRecord::Base
    belongs_to :user_device
  end

  class UserDevice < ::ActiveRecord::Base
    has_many :oauth2_authorizations
  end

  def change
    create_table :user_devices do |t|
      t.references  :user,                     null: false
      t.references  :token,                    null: true
      t.string      :client_ip_addr,           null: false, limit: 46
      t.string      :client_ip_ptr,            null: false, limit: 255
      t.references  :user_agent,               null: false
      t.boolean     :known,                    null: false, default: false
      t.timestamps                             null: false
    end

    add_column :oauth2_authorizations, :user_device_id, :bigint, null: true
    add_index :oauth2_authorizations, :user_device_id

    reversible do |dir|
      dir.up do
        # Create a device per authorization
        Oauth2Authorization.all.each do |auth|
          next unless auth.user_agent_id

          device = UserDevice.create!(
            user_id: auth.user_id,
            token_id: nil,
            client_ip_addr: auth.client_ip_addr,
            client_ip_ptr: auth.client_ip_ptr,
            user_agent_id: auth.user_agent_id,
            known: true,
            created_at: auth.created_at,
            updated_at: auth.updated_at
          )

          auth.update!(user_device_id: device.id)
        end
      end

      dir.down do
        Oauth2Authorization.all.includes(:user_device).each do |auth|
          next unless auth.user_device_id

          auth.update!(user_agent_id: auth.user_device.user_agent_id)
        end
      end
    end

    remove_column :oauth2_authorizations, :user_agent_id, :bigint, null: true
  end
end
