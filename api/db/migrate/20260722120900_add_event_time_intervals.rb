class AddEventTimeIntervals < ActiveRecord::Migration[8.1]
  def change
    create_table :event_time_intervals,
                 charset: 'utf8mb3', collation: 'utf8mb3_czech_ci' do |t|
      t.references :user, null: false
      t.string :name, null: false, limit: 255
      t.string :time_zone, null: false, limit: 255
      t.text :specs, null: false
      t.timestamps null: false
    end

    add_index :event_time_intervals, %i[user_id name],
              unique: true,
              name: :index_event_time_intervals_on_user_name

    create_table :event_route_time_intervals,
                 charset: 'utf8mb3', collation: 'utf8mb3_czech_ci' do |t|
      t.references :event_route, null: false,
                                 index: { name: :idx_route_time_intervals_on_route },
                                 foreign_key: { on_delete: :cascade }
      t.references :event_time_interval, null: false,
                                         index: { name: :idx_route_time_intervals_on_interval },
                                         foreign_key: { on_delete: :restrict }
      t.integer :mode, null: false
      t.timestamps null: false
    end

    add_index :event_route_time_intervals,
              %i[event_route_id event_time_interval_id],
              unique: true,
              name: :idx_route_time_intervals_unique
    add_index :event_route_time_intervals, %i[event_route_id mode],
              name: :idx_route_time_intervals_on_route_mode

    add_column :event_route_matches, :time_interval_state, :string,
               null: false, default: 'active', limit: 32
    add_column :event_route_matches, :time_interval_snapshot, :text
    add_index :event_route_matches, :time_interval_state,
              name: :idx_event_route_matches_on_time_state
  end
end
