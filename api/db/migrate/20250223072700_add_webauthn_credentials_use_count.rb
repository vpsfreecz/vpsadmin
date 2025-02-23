class AddWebauthnCredentialsUseCount < ActiveRecord::Migration[7.2]
  def change
    add_column :webauthn_credentials, :use_count, :bigint, null: false, default: 0

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('UPDATE webauthn_credentials SET use_count = sign_count')
      end
    end
  end
end
