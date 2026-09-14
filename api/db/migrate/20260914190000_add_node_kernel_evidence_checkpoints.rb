class AddNodeKernelEvidenceCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :node_kernel_evidence_checkpoints do |t|
      t.integer :node_id, unsigned: true, null: false
      t.text :report, size: :long, null: false
      t.datetime :observed_at, null: false
      t.index :node_id, unique: true
    end
    add_foreign_key :node_kernel_evidence_checkpoints, :nodes, on_delete: :cascade
  end
end
