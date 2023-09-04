class AddIncidentReportsFromCli < ActiveRecord::Migration[7.0]
  def change
    add_column :incident_reports, :reported_at, :datetime, null: true
    add_column :incident_reports, :cpu_limit, :integer, null: true

    add_index :incident_reports, :reported_at
    add_index :incident_reports, :cpu_limit

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute(
          'UPDATE incident_reports SET reported_at = created_at'
        )
      end
    end
  end
end
