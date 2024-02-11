class RemoveSessionTokens < ActiveRecord::Migration[7.0]
  class Token < ::ActiveRecord::Base; end

  class SessionToken < ::ActiveRecord::Base; end

  class UserSession < ::ActiveRecord::Base; end

  def change
    add_column :user_sessions, :label, :string, null: false, default: '', limit: 255
    add_column :user_sessions, :request_count, :integer, null: false, default: 0
    add_column :user_sessions, :token_id, :integer, null: true
    add_column :user_sessions, :token_lifetime, :integer, null: false, default: 0
    add_column :user_sessions, :token_interval, :integer, null: true

    add_index :user_sessions, :token_id

    reversible do |dir|
      # Transfer session tokens into user sessions
      dir.up do
        rename_column :user_sessions, :session_token_str, :token_str

        SessionToken.all.each do |session_token|
          puts "SessionToken ##{session_token.id}"

          user_session = UserSession.find_by(session_token_id: session_token.id)

          if user_session.nil?
            puts '  user session not found'
            Token.where(id: session_token.token_id).delete_all
            next
          else
            puts "  -> user session ##{user_session.id}"
          end

          user_session.update!(
            label: session_token.label || '',
            request_count: session_token.use_count,
            token_id: session_token.token_id,
            token_lifetime: session_token.lifetime,
            token_interval: session_token.interval
          )

          Token.where(
            owner_type: 'SessionToken',
            owner_id: session_token.id
          ).update_all(
            owner_type: 'UserSession',
            owner_id: user_session.id
          )
        end
      end

      # Transfer user sessions back into session tokens
      dir.down do
        rename_column :user_sessions, :token_str, :session_token_str

        UserSession.where.not(token_id: nil).each do |user_session|
          puts "User session ##{user_session.id}"

          session_token = SessionToken.create!(
            user_id: user_session.user_id,
            token_id: user_session.token_id,
            label: user_session.label.empty? ? nil : user_session.label,
            use_count: user_session.request_count,
            lifetime: user_session.token_lifetime,
            interval: user_session.token_interval
          )

          puts "  -> session token ##{session_token.id}"

          user_session.update!(
            session_token_id: session_token.id
          )

          Token.where(
            owner_type: 'UserSession',
            owner_id: user_session.id
          ).update_all(
            owner_type: 'SessionToken',
            owner_id: session_token.id
          )
        end
      end
    end

    remove_column :user_sessions, :session_token_id, :integer, null: true

    drop_table :session_tokens do |t|
      t.references  :user,                       null: false
      t.references  :token,                      null: false
      t.string      :label,                      null: true, limit: 255
      t.integer     :use_count,                  null: false, default: 0
      t.integer     :lifetime,                   null: false
      t.integer     :interval,                   null: true
      t.timestamps
    end
  end
end
