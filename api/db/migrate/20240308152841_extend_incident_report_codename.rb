class ExtendIncidentReportCodename < ActiveRecord::Migration[7.1]
  def up
    change_column :incident_reports, :codename, :string, null: true, limit: 100
  end

  def down
    change_column :incident_reports, :codename, :string, null: true, limit: 50
  end
end
