class AddSecurityAdvisoryContentRevision < ActiveRecord::Migration[8.1]
  def change
    add_column :security_advisories, :content_revision, :integer, null: false, default: 0
  end
end
