# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260713120200_add_node_kernel_evidence')

RSpec.describe AddNodeKernelEvidence do
  before do
    define_schema do
      create_table :nodes
      create_table :node_current_statuses do |t|
        t.references :node, null: false
      end
      create_table :node_kernel_events do |t|
        t.references :node, null: false
      end
    end
  end

  it 'adds normalized current and event kernel evidence' do
    migrate_up!

    expect(table_exists?(:node_kernel_evidences)).to be(true)
    expect(column(:node_kernel_evidences, :report_schema_version).null).to be(false)
    expect(column(:node_kernel_evidences, :snapshot_revision).null).to be(false)
    expect(column_exists?(:node_current_statuses, :node_kernel_evidence_id)).to be(true)
    expect(column_exists?(:node_kernel_events, :node_kernel_evidence_id)).to be(true)
    expect(table_exists?(:node_kernel_parameters)).to be(true)
    expect(table_exists?(:node_kernel_modules)).to be(true)
    expect(table_exists?(:node_sysctls)).to be(true)
    expect(table_exists?(:node_sysctl_changes)).to be(true)
    expect(table_exists?(:node_software_versions)).to be(true)
    expect(table_exists?(:node_software_changes)).to be(true)
    expect(table_exists?(:node_kernel_livepatches)).to be(true)
    expect(table_exists?(:node_kernel_livepatch_patches)).to be(true)
    expect(table_exists?(:node_ebpf_programs)).to be(true)
    expect(table_exists?(:node_ebpf_program_objects)).to be(true)
    expect(table_exists?(:node_ebpf_program_links)).to be(true)
    expect(table_exists?(:node_kernel_evidence_errors)).to be(true)
    expect(connection.table_options(:node_kernel_evidences).fetch(:collation)).to eq(
      'utf8mb3_bin'
    )
    expect(connection.table_options(:node_kernel_modules).fetch(:collation)).to eq(
      'utf8mb3_bin'
    )

    expect(column(:node_kernel_parameters, :position).null).to be(false)
    expect(column_exists?(:node_kernel_parameters, :origin)).to be(false)
    expect(column(:node_kernel_parameters, :name).null).to be(false)
    expect(column(:node_kernel_parameters, :value).null).to be(true)
    parameter_index = connection.indexes(:node_kernel_parameters).find do |candidate|
      candidate.name == 'idx_node_kernel_parameters_position'
    end
    expect(parameter_index.columns).to eq(%w[node_kernel_evidence_id position])
    expect(parameter_index.unique).to be(true)

    index = connection.indexes(:node_kernel_modules).find do |candidate|
      candidate.name == 'idx_node_kernel_module_unique'
    end
    expect(index.columns).to eq(%w[node_kernel_evidence_id name])
    expect(index.unique).to be(true)

    software_index = connection.indexes(:node_software_versions).find do |candidate|
      candidate.name == 'idx_node_software_versions_unique'
    end
    expect(software_index.columns).to eq(
      %w[node_kernel_evidence_id generation component]
    )
    expect(software_index.unique).to be(true)
    expect(column(:node_software_versions, :revision_dirty).default).to be(false)
    expect(column(:node_software_versions, :revision_dirty).null).to be(false)
  end

  it 'removes normalized evidence on rollback' do
    migrate_up!
    migrate_down!

    expect(table_exists?(:node_kernel_evidences)).to be(false)
    expect(table_exists?(:node_kernel_modules)).to be(false)
    expect(column_exists?(:node_current_statuses, :node_kernel_evidence_id)).to be(false)
    expect(column_exists?(:node_kernel_events, :node_kernel_evidence_id)).to be(false)
  end
end
