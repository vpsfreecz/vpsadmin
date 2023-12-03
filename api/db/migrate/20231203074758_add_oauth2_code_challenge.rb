class AddOauth2CodeChallenge < ActiveRecord::Migration[7.0]
  def change
    add_column :oauth2_authorizations, :code_challenge, :string, null: true, limit: 255
    add_column :oauth2_authorizations, :code_challenge_method, :string, null: true, limit: 20
  end
end
