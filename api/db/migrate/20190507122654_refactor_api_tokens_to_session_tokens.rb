class RefactorApiTokensToSessionTokens < ActiveRecord::Migration
  class SessionToken < ActiveRecord::Base ; end
  class Token < ActiveRecord::Base ; end

  def up
    rename_table :api_tokens, :session_tokens
    add_column :session_tokens, :token_id, :integer, null: true

    SessionToken.all.each do |st|
      t = Token.create!(
        token: st.token,
        valid_to: st.valid_to,
        owner_type: 'SessionToken',
        owner_id: st.id,
        created_at: st.created_at,
      )

      st.update!(token_id: t.id)
    end

    change_column_null :session_tokens, :token_id, false

    remove_column :session_tokens, :token
    remove_column :session_tokens, :valid_to
    rename_column :user_sessions, :api_token_id, :session_token_id
    rename_column :user_sessions, :api_token_str, :session_token_str
  end

  def down
    add_column :session_tokens, :token, :string, null: false, limit: 100
    add_column :session_tokens, :valid_to, :datetime, null: true

    SessionToken.all.each do |st|
      t = Token.find(st.token_id)

      st.update!(
        token: t.token,
        valid_to: t.valid_to,
      )

      t.destroy!
    end

    remove_column :session_tokens, :token_id
    rename_column :user_sessions, :session_token_id, :api_token_id
    rename_column :user_sessions, :session_token_str, :api_token_str
    rename_table :session_tokens, :api_tokens
  end
end
