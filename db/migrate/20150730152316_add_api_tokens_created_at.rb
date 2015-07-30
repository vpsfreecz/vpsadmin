class AddApiTokensCreatedAt < ActiveRecord::Migration
  def change
    add_column :api_tokens, :created_at, :datetime, null: true
  end
end
