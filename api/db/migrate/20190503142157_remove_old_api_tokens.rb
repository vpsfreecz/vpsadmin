class RemoveOldApiTokens < ActiveRecord::Migration
  def up
    ActiveRecord::Base.connection.execute('
      DELETE api_tokens
      FROM api_tokens
      INNER JOIN users ON users.id = api_tokens.user_id
      WHERE users.object_state > 1
    ')
  end

  def down
  end
end
