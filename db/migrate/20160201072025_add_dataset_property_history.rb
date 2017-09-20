class AddDatasetPropertyHistory < ActiveRecord::Migration
  def change
    create_table :dataset_property_histories do |t|
      t.references  :dataset_property,       null: false
      t.integer     :value,                  null: false
      t.datetime    :created_at,             null: false
    end
  end
end
