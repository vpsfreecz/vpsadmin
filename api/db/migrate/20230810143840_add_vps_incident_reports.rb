class AddVpsIncidentReports < ActiveRecord::Migration[7.0]
  def change
    create_table :incident_reports do |t|
      t.references  :user,                        null: false
      t.references  :vps,                         null: false
      t.references  :ip_address_assignment,       null: true
      t.references  :filed_by,                    null: true
      t.references  :mailbox,                     null: true
      t.string      :subject,                     null: false, limit: 255
      t.text        :text,                        null: false
      t.string      :codename,                    null: true, limit: 50
      t.datetime    :detected_at,                 null: false
      t.timestamps                                null: false
    end

    add_index :incident_reports, :created_at
    add_index :incident_reports, :detected_at
  end
end
