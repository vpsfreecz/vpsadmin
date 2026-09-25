# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::GroupSnapshot do
  it 'commits three signed API-produced chains for the node consumer', :no_transaction do
    private_dir = ENV.fetch('CONTRACT_PRIVATE_DIR')
    node = SpecSeed.node
    unlock_transaction_signer!

    allow(Transactions::Storage::CreateSnapshots)
      .to receive(:test_only_strict_group_snapshot?).and_return(true)

    scenarios = %w[success partial tampered].map do |scenario|
      pool = create_pool!(node:, role: :primary)
      members = 2.times.map do |index|
        _, dip = create_dataset_with_pool!(
          user: SpecSeed.user, pool:,
          name: "contract-#{scenario}-#{index}-#{SecureRandom.hex(3)}"
        )
        owner_path = "#{pool.filesystem}/#{dip.dataset.full_name}"
        owner_guid = 50_000 + dip.id
        StorageFilesystemIdentity.create!(
          pool:, dataset_in_pool: dip, zfs_path: owner_path,
          zfs_guid: owner_guid, physical_presence: :present
        )
        { dip:, owner_path:, owner_guid: }
      end

      chain, sips = with_current_context do
        dips = members.map { |row| row.fetch(:dip) }
        described_class.fire(dips, strict: true)
      end
      transaction = chain.transactions.sole
      input = JSON.parse(transaction.input).fetch('input')
      intent = StorageMutationIntent.find_by!(transaction_id: transaction.id)
      targets = intent.storage_mutation_targets.order(:sequence).to_a

      expect(transaction.handle).to eq(5215)
      expect(transaction.signature).not_to be_nil
      expect(targets.map(&:kind)).to eq(%w[observer_unbounded snapshot_create snapshot_create])
      expect(targets.drop(1).map(&:snapshot_in_pool_id)).to eq(sips.sort_by(&:id).map(&:id))

      {
        'scenario' => scenario,
        'node_id' => node.id,
        'chain_id' => chain.id,
        'transaction_id' => transaction.id,
        'intent_id' => intent.id,
        'members' => targets.drop(1).map do |target|
          sip = sips.find { |item| item.id == target.snapshot_in_pool_id }
          member = members.find { |item| item.fetch(:dip).id == sip.dataset_in_pool_id }
          expected_path = "#{member.fetch(:owner_path)}@#{input.fetch('planned_snapshot_name')}"
          expect(target.expected_path).to eq(expected_path)
          expect(target.expected_owner_fs_guid).to eq(member.fetch(:owner_guid))
          {
            'target_id' => target.id,
            'snapshot_id' => sip.snapshot_id,
            'sip_id' => sip.id,
            'dip_id' => member.fetch(:dip).id,
            'expected_path' => expected_path,
            'owner_guid' => member.fetch(:owner_guid).to_s
          }
        end
      }
    end

    public_key_path = File.join(private_dir, 'transaction-public.pem')
    File.open(public_key_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(signer_private_key.public_key.to_pem)
      file.flush
      file.fsync
    end
    manifest_path = File.join(private_dir, 'producer.json')
    File.open(manifest_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.generate('public_key' => public_key_path, 'scenarios' => scenarios))
      file.flush
      file.fsync
    end
    expect(scenarios.length).to eq(3)
  ensure
    lock_transaction_signer!
  end
end
