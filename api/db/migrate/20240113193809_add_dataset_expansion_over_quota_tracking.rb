class AddDatasetExpansionOverQuotaTracking < ActiveRecord::Migration[7.0]
  class DatasetExpansion < ::ActiveRecord::Base ; end

  def change
    add_column :dataset_expansions, :over_refquota_seconds, :integer, null: false, default: 0
    add_column :dataset_expansions, :max_over_refquota_seconds, :integer, null: true
    add_column :dataset_expansions, :last_over_refquota_check, :datetime, null: true

    reversible do |dir|
      dir.up do
        DatasetExpansion.update_all(max_over_refquota_seconds: 30*24*60*60)
      end

      dir.down do
        DatasetExpansion.all.each do |exp|
          exp.update!(deadline: exp.created_at + 30*24*60*60)
        end
      end
    end

    change_column_null :dataset_expansions, :max_over_refquota_seconds, false
    remove_column :dataset_expansions, :deadline, :datetime, null: true
  end
end
