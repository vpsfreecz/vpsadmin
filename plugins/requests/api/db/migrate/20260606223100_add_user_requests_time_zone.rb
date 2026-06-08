class AddUserRequestsTimeZone < ActiveRecord::Migration[7.2]
  def change
    add_column :user_requests, :time_zone, :string, null: true
  end
end
