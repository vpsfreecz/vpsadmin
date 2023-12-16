class AddAuthTokenPurpose < ActiveRecord::Migration[7.0]
  def change
    add_column :auth_tokens, :purpose, :integer, null: false, default: 0
  end
end
