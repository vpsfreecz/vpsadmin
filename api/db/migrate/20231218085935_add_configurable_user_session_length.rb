class AddConfigurableUserSessionLength < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :preferred_session_length, :integer, null: false, default: 20 * 60
  end
end
