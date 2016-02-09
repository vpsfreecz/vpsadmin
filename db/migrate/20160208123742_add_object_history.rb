class AddObjectHistory < ActiveRecord::Migration
  def change
    create_table :object_histories do |t|
      t.references  :user,              null: true
      t.references  :user_session,      null: true
      t.references  :tracked_object,    null: false, polymorphic: true
      t.string      :event_type,        null: false
      t.text        :event_data,        null: true, limit: 65535
      t.datetime    :created_at,        null: false
    end

    add_index :object_histories, [:tracked_object_id, :tracked_object_type],
              name: :object_histories_tracked_object
    add_index :object_histories, :user_id
    add_index :object_histories, :user_session_id
  end
end
