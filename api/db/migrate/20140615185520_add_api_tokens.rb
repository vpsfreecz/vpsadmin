class AddApiTokens < ActiveRecord::Migration
  def up
    create_table :api_tokens do |t|
      t.references :user,                  null: false
      t.string     :token,    limit: 100,  null: false
      t.datetime   :valid_to,              null: true
      t.string     :label
      t.integer    :use_count,             null: false, default: 0
    end
  end

  def down
    drop_table :api_tokens
  end
end
