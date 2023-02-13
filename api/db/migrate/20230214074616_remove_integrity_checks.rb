class RemoveIntegrityChecks < ActiveRecord::Migration[6.1]
  def change
    drop_table :integrity_facts
    drop_table :integrity_objects
    drop_table :integrity_checks
  end
end
