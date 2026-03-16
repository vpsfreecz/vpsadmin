# frozen_string_literal: true

require 'json'
require 'time'

module SpecTransactions
  class Sample < ::Transaction
    t_type 990_001
    queue :network

    def params(node, name:, at: nil)
      self.node = node

      {
        node_id: node.id,
        name:,
        at:
      }
    end
  end
end

RSpec.describe Transaction do
  let(:node) { SpecSeed.node }

  around do |example|
    with_current_context do
      example.run
    end
  end

  def build_chain
    ::TransactionChain.create!(
      name: 'spec_chain',
      type: 'TransactionChain',
      state: :queued,
      size: 0,
      progress: 0,
      user: ::User.current,
      user_session: ::UserSession.current,
      urgent_rollback: false
    )
  end

  def transaction_opts(name:, **extra)
    {
      args: [node],
      kwargs: { name: },
      urgent: false
    }.merge(extra)
  end

  def user_cluster_resource
    UserClusterResource.find_by!(
      user: SpecSeed.user,
      environment: SpecSeed.environment,
      cluster_resource: ClusterResource.find_by!(name: 'ipv4')
    )
  end

  def cluster_resource_use(**attrs)
    ClusterResourceUse.create!(
      {
        user_cluster_resource: user_cluster_resource,
        class_name: 'Vps',
        table_name: 'vpses',
        row_id: 123,
        value: 1,
        confirmed: :confirm_create,
        enabled: true
      }.merge(attrs)
    )
  end

  describe '.fire_chained' do
    before do
      lock_transaction_signer!
    end

    it 'sets relational metadata and the waiting state' do
      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(
          name: 'demo',
          urgent: true,
          prio: 7,
          reversible: :not_reversible
        )
      )

      expect(transaction.transaction_chain_id).to be_present
      expect(transaction.depends_on_id).to be_nil
      expect(transaction.handle).to eq(990_001)
      expect(transaction.queue).to eq('network')
      expect(transaction.priority).to eq(7)
      expect(transaction.urgent).to be(true)
      expect(transaction.reversible).to eq('not_reversible')
      expect(transaction.done).to eq('waiting')
      expect(transaction.user_id).to eq(::User.current.id)
      expect(transaction.node_id).to eq(node.id)
    end

    it 'stores relational options inside the signed input payload' do
      chain = build_chain

      transaction = SpecTransactions::Sample.fire_chained(
        chain,
        123,
        transaction_opts(name: 'demo', reversible: :keep_going)
      )

      payload = JSON.parse(transaction.input)

      expect(payload).to include(
        'transaction_chain' => chain.id,
        'depends_on' => 123,
        'handle' => 990_001,
        'node' => node.id,
        'reversible' => ::Transaction.reversibles.fetch('keep_going')
      )
      expect(payload.fetch('input')).to include(
        'node_id' => node.id,
        'name' => 'demo'
      )
    end

    it 'creates unsigned transactions when the signer is locked' do
      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'unsigned')
      )

      expect(transaction.signature).to be_nil
    end

    it 'creates unsigned transactions when the transaction key is absent' do
      key = SysConfig.find_by!(category: 'core', name: 'transaction_key')
      original_value = key.value
      key.update_columns(value: nil)

      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'no-key')
      )

      expect(transaction.signature).to be_nil
    ensure
      key.update_columns(value: original_value)
    end

    it 'signs transactions when the signer is unlocked' do
      unlock_transaction_signer!

      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'signed')
      )

      expect(transaction.signature).to be_present
      verify_signature_base64!(transaction.input, transaction.signature)
    end

    it 'creates confirmation rows for API-side helper methods' do
      confirmed_row = cluster_resource_use
      plain_row = ResourceLock.create!(resource: 'SpecLock', row_id: 42)

      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'confirmables')
      ) do
        create(confirmed_row)
        just_create(plain_row)
        destroy(confirmed_row)
        just_destroy(plain_row)
        edit_before(confirmed_row, value: 9)
        edit_after(confirmed_row, confirmed: 1)
        increment(confirmed_row, :value)
        decrement(confirmed_row, :value)
      end

      confirmations = TransactionConfirmation.where(transaction_id: transaction.id).order(:id).to_a

      expect(confirmations.map(&:confirm_type)).to eq(
        %w[
          create_type
          just_create_type
          destroy_type
          just_destroy_type
          edit_before_type
          edit_after_type
          increment_type
          decrement_type
        ]
      )

      expect(confirmations[0].row_pks).to eq('id' => confirmed_row.id)
      expect(confirmations[1].class_name).to eq('ResourceLock')
      expect(confirmations[4].attr_changes).to eq('value' => 9)
      expect(confirmations[5].attr_changes).to eq('confirmed' => 1)
      expect(confirmations[6].attr_changes).to eq('value')
      expect(confirmations[7].attr_changes).to eq('value')
    end

    it 'translates booleans and times inside attr_changes' do
      timestamp = Time.utc(2024, 1, 2, 3, 4, 5)
      row = cluster_resource_use

      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'translated')
      ) do
        edit_after(row, enabled: false, confirmed: true, updated_at: timestamp)
      end

      confirmation = TransactionConfirmation.find_by!(transaction_id: transaction.id)

      expect(confirmation.attr_changes).to eq(
        'enabled' => 0,
        'confirmed' => 1,
        'updated_at' => '2024-01-02 03:04:05'
      )
    end

    it 'serializes composite primary keys into row_pks' do
      accounting = NetworkInterfaceDailyAccounting.new(
        network_interface_id: 555,
        user_id: SpecSeed.user.id,
        year: 2024,
        month: 2,
        day: 29
      )

      transaction = SpecTransactions::Sample.fire_chained(
        build_chain,
        nil,
        transaction_opts(name: 'cpk')
      ) do
        just_create(accounting)
      end

      confirmation = TransactionConfirmation.find_by!(transaction_id: transaction.id)

      expect(confirmation.row_pks).to eq(
        'network_interface_id' => 555,
        'user_id' => SpecSeed.user.id,
        'year' => 2024,
        'month' => 2,
        'day' => 29
      )
    end

    it 'raises when attrs and kwattrs are mixed' do
      row = cluster_resource_use

      expect do
        SpecTransactions::Sample.fire_chained(
          build_chain,
          nil,
          transaction_opts(name: 'mixed')
        ) do
          edit_before(row, { value: 1 }, confirmed: 1)
        end
      end.to raise_error(ArgumentError, /either as a hash or keyword arguments/)
    end
  end
end
