# frozen_string_literal: true

require 'rake'
require_relative '../migration_helper'

RSpec.describe 'fresh storage freeze schema bootstrap' do # rubocop:disable RSpec/DescribeClass
  it 'creates the singleton once and preserves a later freeze and its audit' do
    load File.expand_path('../../db/schema.rb', __dir__)
    expect(row_count(:storage_freeze_controls)).to eq(0)

    rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path('../../lib/vpsadmin/api/tasks/db.rake', __dir__)
    bootstrap = Rake::Task['db:bootstrap:storage_freeze_control']

    bootstrap.invoke
    expect(row_count(:storage_freeze_controls)).to eq(1)
    expect(find_row(:storage_freeze_controls, id: 1)).to include('mode' => 0, 'epoch' => 0)

    connection.execute(<<~SQL)
      UPDATE storage_freeze_controls
      SET mode = 1, epoch = 1, reason = 'maintenance',
          requested_at = '2026-06-15 12:00:00',
          updated_at = '2026-06-15 12:00:00'
      WHERE id = 1
    SQL
    insert_row(:storage_freeze_transitions,
               storage_freeze_control_id: 1, prior_mode: 0, new_mode: 1,
               prior_epoch: 0, new_epoch: 1, actor_user_id: 7,
               actor_user_session_id: 9, actor_user_login: 'admin',
               reason: 'maintenance', created_at: timestamp)
    control_before = find_row(:storage_freeze_controls, id: 1)
    transition_before = find_row(:storage_freeze_transitions)

    bootstrap.reenable
    bootstrap.invoke
    expect(find_row(:storage_freeze_controls, id: 1)).to eq(control_before)
    expect(row_count(:storage_freeze_controls)).to eq(1)
    expect(find_row(:storage_freeze_transitions)).to eq(transition_before)
  ensure
    Rake.application = rake_application if rake_application
  end

  it 'runs bootstrap only after fresh schema load and before the marker' do
    setup = File.read(File.expand_path('../../../nixos/modules/vpsadmin/database-setup.nix', __dir__))
    fresh_branch = setup.split('echo "Loading database schema"', 2).last
                        .split('echo "Running database migrations"', 2).first

    expect(fresh_branch).to match(
      /rake db:schema:load.*rake db:bootstrap:storage_freeze_control \|\| exit 1.*date > "\$dbStateFile"/m
    )
    expect(setup.scan('rake db:bootstrap:storage_freeze_control').length).to eq(1)
  end
end
