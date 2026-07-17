class AddSecurityAdvisoryExternalId < ActiveRecord::Migration[8.1]
  def change
    add_column :security_advisories, :external_id, :string, limit: 255
    add_index :security_advisories, :external_id, unique: true
  end
end
