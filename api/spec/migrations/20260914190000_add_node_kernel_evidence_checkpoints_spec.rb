# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260914190000_add_node_kernel_evidence_checkpoints')

RSpec.describe AddNodeKernelEvidenceCheckpoints do
  before do
    define_schema do
      create_table :nodes, id: { type: :integer, unsigned: true }
    end
    insert_row(:nodes, id: 400)
  end

  it 'starts empty, enforces one checkpoint per node, cascades deletion, and rolls back' do
    migrate_up!
    expect(rows(:node_kernel_evidence_checkpoints)).to be_empty
    expect(column(:node_kernel_evidence_checkpoints, :observed_at).default).to be_nil
    attrs = { node_id: 400, report: '{}', observed_at: timestamp }
    insert_row(:node_kernel_evidence_checkpoints, attrs)
    expect { insert_row(:node_kernel_evidence_checkpoints, attrs) }
      .to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert_row(:node_kernel_evidence_checkpoints, attrs.merge(node_id: 401)) }
      .to raise_error(ActiveRecord::InvalidForeignKey)
    connection.execute('DELETE FROM nodes WHERE id = 400')
    expect(rows(:node_kernel_evidence_checkpoints)).to be_empty

    migrate_down!
    expect(table_exists?(:node_kernel_evidence_checkpoints)).to be(false)
    expect(table_exists?(:nodes)).to be(true)
  end
end
