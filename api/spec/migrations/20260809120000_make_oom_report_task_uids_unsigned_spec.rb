# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260809120000_make_oom_report_task_uids_unsigned')

RSpec.describe MakeOomReportTaskUidsUnsigned do
  let(:observed_host_uid) { 2_147_756_930 }
  let(:max_mappable_uid) { (2**32) - 2 }

  before do
    define_schema do
      create_table :oom_report_tasks do |t|
        t.integer :host_uid, null: false
        t.integer :vps_uid, null: true
      end
    end
  end

  it 'preserves existing UIDs and stores the unsigned 32-bit range' do
    original_id = insert_row(:oom_report_tasks, host_uid: 1000, vps_uid: nil)

    migrate_up!

    expect(column(:oom_report_tasks, :host_uid)).to have_attributes(
      type: :integer,
      limit: 4,
      null: false,
      unsigned?: true
    )
    expect(column(:oom_report_tasks, :vps_uid)).to have_attributes(
      type: :integer,
      limit: 4,
      null: true,
      unsigned?: true
    )
    expect(find_row(:oom_report_tasks, id: original_id)).to include(
      'host_uid' => 1000,
      'vps_uid' => nil
    )

    high_id = insert_row(
      :oom_report_tasks,
      host_uid: observed_host_uid,
      vps_uid: max_mappable_uid
    )
    expect(find_row(:oom_report_tasks, id: high_id)).to include(
      'host_uid' => observed_host_uid,
      'vps_uid' => max_mappable_uid
    )
  end

  it 'refuses to reinterpret negative predecessor data' do
    id = insert_row(:oom_report_tasks, host_uid: -1, vps_uid: nil)

    expect { migrate_up! }.to raise_error(ActiveRecord::MigrationError, /negative/)

    expect(column(:oom_report_tasks, :host_uid).unsigned?).to be(false)
    expect(find_row(:oom_report_tasks, id: id).fetch('host_uid')).to eq(-1)
  end

  it 'restores signed columns when all values fit' do
    id = insert_row(:oom_report_tasks, host_uid: 1000, vps_uid: 0)
    migrate_up!

    migrate_down!

    expect(column(:oom_report_tasks, :host_uid)).to have_attributes(null: false, unsigned?: false)
    expect(column(:oom_report_tasks, :vps_uid)).to have_attributes(null: true, unsigned?: false)
    expect(find_row(:oom_report_tasks, id: id)).to include(
      'host_uid' => 1000,
      'vps_uid' => 0
    )
  end

  it 'refuses a lossy rollback after a high UID is stored' do
    migrate_up!
    id = insert_row(:oom_report_tasks, host_uid: observed_host_uid, vps_uid: nil)

    expect { migrate_down! }.to raise_error(
      ActiveRecord::IrreversibleMigration,
      /outside the signed 32-bit range/
    )

    expect(column(:oom_report_tasks, :host_uid).unsigned?).to be(true)
    expect(find_row(:oom_report_tasks, id: id).fetch('host_uid')).to eq(observed_host_uid)
  end
end
