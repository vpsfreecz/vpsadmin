# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260823170000_widen_oom_report_task_memory_counters')

RSpec.describe WidenOomReportTaskMemoryCounters do
  let(:memory_columns) { described_class::MEMORY_COLUMNS }
  let(:large_value) { 2_148_035_000 }

  before do
    definitions = described_class::MEMORY_COLUMNS

    define_schema do
      create_table :oom_report_tasks do |t|
        definitions.each do |name, options|
          t.integer name, **options
        end
      end
    end
  end

  it 'preserves rows and stores unsigned 64-bit memory counters' do
    original_id = insert_row(:oom_report_tasks, memory_values(total_vm: 10_000, rss_anon: nil))

    migrate_up!

    memory_columns.each do |name, options|
      expect(column(:oom_report_tasks, name)).to have_attributes(
        type: :integer,
        limit: 8,
        null: options.fetch(:null),
        unsigned?: true
      )
    end
    expect(find_row(:oom_report_tasks, id: original_id)).to include(
      'total_vm' => 10_000,
      'rss_anon' => nil
    )

    large_id = insert_row(:oom_report_tasks, memory_values(total_vm: large_value))
    expect(find_row(:oom_report_tasks, id: large_id).fetch('total_vm')).to eq(large_value)
  end

  it 'refuses to reinterpret negative predecessor data' do
    id = insert_row(:oom_report_tasks, memory_values(swapents: -1))

    expect { migrate_up! }.to raise_error(ActiveRecord::MigrationError, /negative/)

    expect(column(:oom_report_tasks, :total_vm)).to have_attributes(limit: 4, unsigned?: false)
    expect(find_row(:oom_report_tasks, id: id).fetch('swapents')).to eq(-1)
  end

  it 'restores signed integers when all values fit' do
    id = insert_row(:oom_report_tasks, memory_values(rss_anon: nil))
    migrate_up!

    migrate_down!

    memory_columns.each do |name, options|
      expect(column(:oom_report_tasks, name)).to have_attributes(
        limit: 4,
        null: options.fetch(:null),
        unsigned?: false
      )
    end
    expect(find_row(:oom_report_tasks, id: id).fetch('rss_anon')).to be_nil
  end

  it 'refuses a lossy rollback after a large counter is stored' do
    migrate_up!
    id = insert_row(:oom_report_tasks, memory_values(total_vm: large_value))

    expect { migrate_down! }.to raise_error(
      ActiveRecord::IrreversibleMigration,
      /outside the signed 32-bit range/
    )

    expect(column(:oom_report_tasks, :total_vm)).to have_attributes(limit: 8, unsigned?: true)
    expect(find_row(:oom_report_tasks, id: id).fetch('total_vm')).to eq(large_value)
  end

  def memory_values(**overrides)
    memory_columns.to_h { |name, _options| [name, 0] }.merge(overrides)
  end
end
