class AddLifetimesRemindAfterDate < ActiveRecord::Migration[6.1]
  def change
    tables = %i(
      object_states datasets exports mounts snapshot_downloads users vpses
    )

    tables.each do |t|
      add_column t, :remind_after_date, :datetime, null: true
    end
  end
end
