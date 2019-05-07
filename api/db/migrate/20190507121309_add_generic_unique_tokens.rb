class AddGenericUniqueTokens < ActiveRecord::Migration
  def change
    create_table :tokens do |t|
      t.string      :token,         null: false, limit: 100
      t.datetime    :valid_to,      null: true
      t.references  :owner,         null: true,  polymorphic: true, index: true
      t.datetime    :created_at,    null: false
    end

    add_index :tokens, :token, unique: true
  end
end
