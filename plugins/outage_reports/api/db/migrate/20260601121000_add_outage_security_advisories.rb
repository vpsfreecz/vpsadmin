class AddOutageSecurityAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :outage_security_advisories do |t|
      t.references :outage, null: false, index: false
      t.references :security_advisory, null: false, index: false
    end

    add_index :outage_security_advisories,
              %i[outage_id security_advisory_id],
              unique: true,
              name: 'index_osa_on_outage_advisory'
    add_index :outage_security_advisories, :security_advisory_id
  end
end
