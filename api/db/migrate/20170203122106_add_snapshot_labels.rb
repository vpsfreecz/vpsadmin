class AddSnapshotLabels < ActiveRecord::Migration
  def change
    add_column :snapshots, :label, :string, null: true, limit: 255
  end
end
