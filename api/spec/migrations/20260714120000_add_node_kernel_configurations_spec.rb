# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260714120000_add_node_kernel_configurations')

RSpec.describe AddNodeKernelConfigurations do
  before do
    define_schema do
      create_table :node_current_statuses do |t|
        t.string :kernel, null: false
      end
      create_table :node_statuses do |t|
        t.string :kernel, null: false
      end
    end
  end

  it 'makes current service kernels optional and adds a deduplicated config catalog' do
    migrate_up!

    expect(column(:node_current_statuses, :kernel).null).to be(true)
    expect(column(:node_statuses, :kernel).null).to be(false)
    expect(table_exists?(:node_kernel_configurations)).to be(true)
    expect(table_exists?(:node_kernel_configuration_options)).to be(true)
    expect(column(:node_kernel_configurations, :content).limit).to eq(16_777_215)
    expect(index_exists?(:node_kernel_configurations, [:digest])).to be(true)
    expect(connection.table_options(:node_kernel_configurations).fetch(:collation)).to eq(
      'utf8mb3_bin'
    )
  end

  it 'restores non-null kernels on rollback without losing service rows' do
    migrate_up!
    insert_row(:node_current_statuses, kernel: nil)
    insert_row(:node_statuses, kernel: '')

    migrate_down!

    expect(column(:node_current_statuses, :kernel).null).to be(false)
    expect(column(:node_statuses, :kernel).null).to be(false)
    expect(find_row(:node_current_statuses).fetch('kernel')).to eq('')
    expect(find_row(:node_statuses).fetch('kernel')).to eq('')
    expect(table_exists?(:node_kernel_configurations)).to be(false)
    expect(table_exists?(:node_kernel_configuration_options)).to be(false)
  end
end
