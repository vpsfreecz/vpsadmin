''
  def preview_snapshot_removal(dataset_id, **options)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset', 'preview_snapshot_removal', dataset_id.to_s],
      parameters: options
    )
    expect(action_state_id(output)).to be_nil
    preview = output.fetch('dataset')
    expect(preview.fetch('manifest_version')).to eq(1)
    expect(preview.fetch('manifest_digest')).to match(/\Av1:[0-9a-f]{64}\z/)
    preview
  end

  def remove_reviewed_snapshots(dataset_id, preview, **options)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset', 'remove_snapshots', dataset_id.to_s],
      opts: { block: false },
      parameters: options.merge(manifest_digest: preview.fetch('manifest_digest'))
    )
    id = action_state_id(output)
    expect(id).not_to be_nil, output.inspect
    id
  end

  def expect_removal_done(chain_id)
    state = wait_for_chain_states_local(services, chain_id, %i[done failed fatal resolved], timeout: 1200)
    expect(state).to eq(services.class::CHAIN_STATES.fetch(:done)), chain_failure_details(services, chain_id).inspect
    expect(chain_failure_details(services, chain_id)).to be_empty
    wait_for_chain_locks_released(services, chain_id)
  end

  def removal_chain_count
    services.mariadb_scalar(
      sql: "SELECT COUNT(*) FROM transaction_chains WHERE type = 'TransactionChains::Dataset::RemoveSnapshots'"
    )
  end

  def expect_removal_order(chain_id, preview)
    commands = services.api_ruby_json(code: <<~RUBY)
      handles = [Transactions::Storage::DestroySnapshot.t_type,
                 Transactions::Storage::DestroyBranch.t_type, Transactions::Storage::DestroyTree.t_type]
      rows = Transaction.where(transaction_chain_id: #{Integer(chain_id)}, handle: handles).order(:id).map do |tx|
        { id: tx.id, handle: tx.handle, branch_destroy: tx.handle == Transactions::Storage::DestroyBranch.t_type,
          input: JSON.parse(tx.input).fetch('input') }
      end
      puts JSON.dump(rows)
    RUBY
    manifest = preview.fetch('manifest')
    copies = manifest.fetch('copies').to_h { |row| [row.fetch('id'), row] }
    trees = manifest.fetch('trees').to_h { |row| [row.fetch('id'), row] }
    branches = manifest.fetch('branches').to_h { |row| [row.fetch('id'), row] }
    locations = manifest.fetch('snapshot_locations').to_h { |row| [row.fetch('snapshot_in_pool_in_branch_id'), row] }
    source_pools = copies.values.reject { |row| row.fetch('pool_role') == 'backup' }.map { |row| row.fetch('pool_filesystem') }
    source, backup = commands.partition { |row| source_pools.include?(row.fetch('input').fetch('pool_fs')) }
    expect(source.map { |row| row.fetch('id') }.min).to be > backup.map { |row| row.fetch('id') }.max if source.any? && backup.any?

    locations.values.each do |location|
      origin_id = location.fetch('origin_snapshot_in_pool_in_branch_id')
      next unless origin_id

      origin = locations.fetch(origin_id)
      child_branch = branches.fetch(location.fetch('branch_id'))
      origin_branch = branches.fetch(origin.fetch('branch_id'))
      pool_fs = copies.fetch(location.fetch('dataset_in_pool_id')).fetch('pool_filesystem')
      branch_command = commands.find do |row|
        input = row.fetch('input')
        row.fetch('branch_destroy') && input.fetch('pool_fs') == pool_fs &&
          input.fetch('tree') == trees.fetch(child_branch.fetch('dataset_tree_id')).fetch('name') &&
          input.fetch('branch') == child_branch.fetch('name')
      end
      origin_command = commands.find do |row|
        input = row.fetch('input')
        row.fetch('handle') == tx_types(services).fetch('destroy_snapshot') && input.fetch('pool_fs') == pool_fs &&
          input['tree'] == trees.fetch(origin_branch.fetch('dataset_tree_id')).fetch('name') &&
          input['branch'] == origin_branch.fetch('name') && input.fetch('snapshot').fetch('id') == origin.fetch('snapshot_id')
      end
      expect(branch_command).not_to be_nil
      expect(origin_command).not_to be_nil
      expect(branch_command.fetch('id')).to be < origin_command.fetch('id')
    end
  end

  def source_proof(dataset_id, dip_id, path)
    _, properties = node1.succeeds(
      "zfs get -H -p -o property,value guid,refquota,quota,reservation,refreservation,compression " \
      "#{Shellwords.escape(path)}", timeout: 60
    )
    identity = services.api_ruby_json(code: <<~RUBY)
      d = Dataset.find(#{Integer(dataset_id)})
      puts JSON.dump(id: d.id, user_id: d.user_id, ancestry: d.ancestry,
                     name: d.name, current_history_id: d.current_history_id,
                     object_state: d.object_state)
    RUBY
    {
      'dataset' => identity,
      'copy' => dataset_in_pool_row(services, dip_id),
      'properties' => properties,
      'text' => read_dataset_text(node1, dataset_path: path, relative_path: 'var/tmp/removal-marker'),
      'checksum' => file_checksum(node1, dataset_path: path, relative_path: 'var/tmp/removal-marker')
    }
  end

  def backup_storage_proof(dip_id, path)
    report = backup_topology_report(services, backup_node: node2, dst_dip_id: dip_id, backup_dataset_path: path)
    _, output = node2.succeeds(
      "zfs list -H -r -t filesystem,snapshot -o name #{Shellwords.escape(path)}", timeout: 60
    )
    # Logical child datasets share the path prefix but are a separate scope.
    physical = output.lines.map(&:strip).select { |name| name == path || name.start_with?("#{path}/tree.") }.sort
    expected = [path]
    report.fetch('db').fetch('trees').each { |tree| expected << "#{path}/tree.#{tree.fetch('index')}" }
    report.fetch('db').fetch('branches').each do |branch|
      expected << "#{path}/tree.#{branch.fetch('tree_index')}/branch-#{branch.fetch('name')}.#{branch.fetch('index')}"
    end
    report.fetch('db').fetch('entries').each do |entry|
      expected << "#{path}/tree.#{entry.fetch('tree_index')}/branch-#{entry.fetch('branch_name')}.#{entry.fetch('branch_index')}@#{entry.fetch('snapshot_name')}"
    end
    expect(physical).to eq(expected.sort), report.inspect
    report.merge('physical' => physical, 'snapshots' => snapshot_rows_for_dip(services, dip_id))
  end

  def expect_history_removed(dataset_id, src_dip_id, source_path, backups)
    expect(snapshot_rows_for_dip(services, src_dip_id)).to be_empty
    _, output = node1.succeeds(
      "zfs list -H -r -t snapshot -o name #{Shellwords.escape(source_path)}", timeout: 60
    )
    expect(output.lines.map(&:strip).grep(/^#{Regexp.escape(source_path)}@/)).to be_empty
    backups.each do |dip_id, path|
      report = backup_storage_proof(dip_id, path)
      expect(report.fetch('db').values).to all(be_empty)
      expect(report.fetch('snapshots')).to be_empty
      expect(report.fetch('physical')).to eq([path])
      expect(dataset_in_pool_row(services, dip_id).fetch('dataset_id')).to eq(dataset_id)
    end
    expect(services.mariadb_scalar(sql: "SELECT COUNT(*) FROM snapshots WHERE dataset_id = #{Integer(dataset_id)}")).to eq('0')
  end

  def add_shared_and_empty_history(dip_id, path)
    original = branch_entries_for_dip(services, dip_id).find { |entry| entry.fetch('parent_entry_id').nil? }
    expect(original).not_to be_nil
    original_path = branch_dataset_path('tank/backup-a', @setup.fetch('dataset_full_name'), original)
    rows = services.api_ruby_json(code: <<~RUBY)
      dip = DatasetInPool.find(#{Integer(dip_id)})
      tree = DatasetTree.create!(dataset_in_pool: dip, index: dip.dataset_trees.maximum(:index).to_i + 1,
                                 head: false, confirmed: :confirmed)
      branch = Branch.create!(dataset_tree: tree, name: 'shared', index: 0, head: false, confirmed: :confirmed)
      entry = SnapshotInPoolInBranch.create!(snapshot_in_pool_id: #{Integer(original.fetch('snapshot_in_pool_id'))},
                                             branch: branch, confirmed: :confirmed)
      empty_branch = Branch.create!(dataset_tree: tree, name: 'empty', index: 0, head: false, confirmed: :confirmed)
      empty_tree = DatasetTree.create!(dataset_in_pool: dip, index: tree.index + 1, head: false, confirmed: :confirmed)
      puts JSON.dump(tree: tree.full_name, branch: branch.full_name, empty_branch: empty_branch.full_name,
                     empty_tree: empty_tree.full_name, entry_id: entry.id,
                     tree_id: tree.id, empty_tree_id: empty_tree.id, empty_branch_id: empty_branch.id)
    RUBY
    tree_path = "#{path}/#{rows.fetch('tree')}"
    node2.succeeds("zfs create #{Shellwords.escape(tree_path)}", timeout: 60)
    node2.succeeds(
      "zfs send #{Shellwords.escape("#{original_path}@#{original.fetch('snapshot_name')}")} | " \
      "zfs recv #{Shellwords.escape("#{tree_path}/#{rows.fetch('branch')}")}", timeout: 300
    )
    node2.succeeds("zfs create #{Shellwords.escape("#{tree_path}/#{rows.fetch('empty_branch')}")}", timeout: 60)
    node2.succeeds("zfs create #{Shellwords.escape("#{path}/#{rows.fetch('empty_tree')}")}", timeout: 60)
    rows
  end

  def cached_plan_jobs(dip_id)
    services.api_ruby_json(code: <<~RUBY)
      source = DatasetInPool.find(#{Integer(dip_id)})
      jobs = source.src_dataset_actions.map { |a| { id: a.id, kind: a.action, destination: a.dst_dataset_in_pool_id } }
      source.group_snapshots.each do |member|
        jobs << { id: member.dataset_action_id, kind: 'group_snapshot', members: [source.id] }
      end
      puts JSON.dump(jobs)
    RUBY
  end

  def run_cached_jobs(jobs, source_id)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}
      jobs = JSON.parse(#{JSON.dump(jobs).inspect})
      chains = jobs.map do |job|
        chain, = if job.fetch('kind') == 'group_snapshot'
          TransactionChains::Dataset::GroupSnapshot.fire(
            DatasetInPool.where(id: job.fetch('members')).to_a, expected_action: job.fetch('id')
          )
        else
          TransactionChains::Dataset::Backup.fire(
            DatasetInPool.find(#{Integer(source_id)}), DatasetInPool.find(job.fetch('destination')),
            expected_action: job.fetch('id')
          )
        end
        chain&.id
      end
      puts JSON.dump(chains)
    RUBY
  end
''
