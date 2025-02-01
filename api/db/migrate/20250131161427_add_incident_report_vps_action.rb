class AddIncidentReportVpsAction < ActiveRecord::Migration[7.2]
  def change
    add_column :incident_reports, :vps_action, :integer, null: false, default: 0
  end
end
