# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/confirmations'
require 'bigdecimal'

module NodeCtldSpec
  CONFIRM_TYPES = {
    create: 0,
    just_create: 1,
    edit_before: 2,
    edit_after: 3,
    destroy: 4,
    just_destroy: 5,
    decrement: 6,
    increment: 7
  }.freeze
end

RSpec.describe NodeCtld::Confirmations do
  def run_confirmations(chain_id, direction)
    described_class.new(chain_id).run(shared_db, direction)
  end

  def force_confirmations(chain_id, transactions, direction, success)
    described_class.new(chain_id).force_run(
      shared_db,
      transactions,
      direction,
      success
    )
  end

  def decimal_value(row_id)
    BigDecimal(sql_value('SELECT value FROM cluster_resource_uses WHERE id = ?', row_id).to_s)
  end

  def confirm_type(name)
    NodeCtldSpec::CONFIRM_TYPES.fetch(name)
  end

  describe '#run' do
    it 'marks create rows confirmed on execute success and leaves other chains untouched' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK,
        done: NodeCtldSpec::TxState::TX_DONE_DONE
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:create)
      )

      other_row_id = insert_cluster_resource_use(value: 20, confirmed: 0)
      other_chain_id = insert_chain
      other_tx_id = insert_transaction(
        transaction_chain_id: other_chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK,
        done: NodeCtldSpec::TxState::TX_DONE_DONE
      )
      insert_confirmation(
        transaction_id: other_tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => other_row_id },
        confirm_type: confirm_type(:create)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
      expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx_id)).to eq(1)
      expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', other_tx_id)).to eq(0)
    end

    it 'deletes create rows on execute failure' do
      row_id = insert_cluster_resource_use
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:create)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
      expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx_id)).to eq(1)
    end

    it 'deletes create rows on rollback' do
      row_id = insert_cluster_resource_use
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK,
        done: NodeCtldSpec::TxState::TX_DONE_ROLLED_BACK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:create)
      )

      run_confirmations(chain_id, :rollback)

      expect(sql_value('SELECT COUNT(*) FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
    end

    it 'keeps just_create rows on execute success' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_create)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(1)
    end

    it 'deletes just_create rows on execute failure' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_create)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(0)
    end

    it 'deletes just_create rows on rollback' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_create)
      )

      run_confirmations(chain_id, :rollback)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(0)
    end

    it 'does not revert edit_before rows on execute success' do
      row_id = insert_cluster_resource_use(value: 15, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 10, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_before)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('15'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
    end

    it 'restores original attrs for edit_before on execute failure' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 1)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 10, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_before)
      )
      sql_update('cluster_resource_uses', { value: 15, confirmed: 0 }, 'id = ?', row_id)

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'restores original attrs for edit_before on rollback' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 1)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK,
        done: NodeCtldSpec::TxState::TX_DONE_DONE
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 10, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_before)
      )
      sql_update('cluster_resource_uses', { value: 15, confirmed: 0 }, 'id = ?', row_id)

      run_confirmations(chain_id, :rollback)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'applies edit_after attrs on execute success' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 20, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_after)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('20'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'does not apply edit_after attrs on execute failure' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 20, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_after)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
    end

    it 'does not apply edit_after attrs on rollback' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 20, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_after)
      )

      run_confirmations(chain_id, :rollback)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
    end

    it 'deletes destroy rows on execute success' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 1)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:destroy)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(0)
    end

    it 'reconfirms destroy rows on execute failure' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:destroy)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'reconfirms destroy rows on rollback' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:destroy)
      )

      run_confirmations(chain_id, :rollback)

      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'deletes just_destroy rows on execute success' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_destroy)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(0)
    end

    it 'leaves just_destroy rows on execute failure' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_destroy)
      )

      run_confirmations(chain_id, :execute)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(1)
    end

    it 'leaves just_destroy rows on rollback' do
      row_id = insert_resource_lock(chain_id: insert_chain)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ResourceLock',
        table_name: 'resource_locks',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:just_destroy)
      )

      run_confirmations(chain_id, :rollback)

      expect(sql_value('SELECT COUNT(*) FROM resource_locks WHERE id = ?', row_id)).to eq(1)
    end

    it 'decrements using the legacy string form on execute success' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: 'value',
        confirm_type: confirm_type(:decrement)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('9'))
    end

    it 'decrements using the hash form on execute success' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:decrement)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('7'))
    end

    it 'does not decrement on execute failure' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:decrement)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
    end

    it 'does not decrement on rollback' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:decrement)
      )

      run_confirmations(chain_id, :rollback)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
    end

    it 'increments using the legacy string form on execute success' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: 'value',
        confirm_type: confirm_type(:increment)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('11'))
    end

    it 'increments using the hash form on execute success' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:increment)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('13'))
    end

    it 'does not increment on execute failure' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_FAILED
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:increment)
      )

      run_confirmations(chain_id, :execute)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
    end

    it 'does not increment on rollback' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain(state: NodeCtldSpec::TxState::CHAIN_ROLLBACKING)
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        status: NodeCtldSpec::TxState::TX_STATUS_OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 3 },
        confirm_type: confirm_type(:increment)
      )

      run_confirmations(chain_id, :rollback)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
    end
  end

  describe '#force_run' do
    it 'returns grouped confirmation metadata for the selected transactions' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      confirmation_id = insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 12 },
        confirm_type: confirm_type(:edit_after)
      )

      ret = force_confirmations(chain_id, [tx_id], :execute, true)

      expect(ret).to eq(
        tx_id => [
          {
            id: confirmation_id,
            class_name: 'ClusterResourceUse',
            row_pks: { 'id' => row_id },
            attr_changes: { 'value' => 12 },
            type: :edit_after,
            done: false
          }
        ]
      )
      expect(sql_value('SELECT done FROM transaction_confirmations WHERE id = ?', confirmation_id)).to eq(1)
    end

    it 'force-applies create confirmations' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 0)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        confirm_type: confirm_type(:create)
      )

      force_confirmations(chain_id, [tx_id], :execute, true)

      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'force-applies edit_before rollback restoration' do
      row_id = insert_cluster_resource_use(value: 10, confirmed: 1)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 10, 'confirmed' => 1 },
        confirm_type: confirm_type(:edit_before)
      )
      sql_update('cluster_resource_uses', { value: 14, confirmed: 0 }, 'id = ?', row_id)

      force_confirmations(chain_id, [tx_id], :rollback, true)

      expect(decimal_value(row_id)).to eq(BigDecimal('10'))
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row_id)).to eq(1)
    end

    it 'force-applies increment hash confirmations' do
      row_id = insert_cluster_resource_use(value: 10)
      chain_id = insert_chain
      tx_id = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      insert_confirmation(
        transaction_id: tx_id,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row_id },
        attr_changes: { 'value' => 5 },
        confirm_type: confirm_type(:increment)
      )

      force_confirmations(chain_id, [tx_id], :execute, true)

      expect(decimal_value(row_id)).to eq(BigDecimal('15'))
    end

    it 'marks only selected transaction confirmations as done' do
      row1 = insert_cluster_resource_use(value: 10, confirmed: 0)
      row2 = insert_cluster_resource_use(value: 20, confirmed: 0)
      chain_id = insert_chain(size: 2)
      tx1 = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK
      )
      tx2 = insert_transaction(
        transaction_chain_id: chain_id,
        handle: NodeCtldSpec::TestHandles::OK,
        depends_on_id: tx1
      )
      insert_confirmation(
        transaction_id: tx1,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row1 },
        confirm_type: confirm_type(:create)
      )
      insert_confirmation(
        transaction_id: tx2,
        class_name: 'ClusterResourceUse',
        table_name: 'cluster_resource_uses',
        row_pks: { 'id' => row2 },
        confirm_type: confirm_type(:create)
      )

      force_confirmations(chain_id, [tx1], :execute, true)

      expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx1)).to eq(1)
      expect(sql_value('SELECT done FROM transaction_confirmations WHERE transaction_id = ?', tx2)).to eq(0)
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row1)).to eq(1)
      expect(sql_value('SELECT confirmed FROM cluster_resource_uses WHERE id = ?', row2)).to eq(0)
    end
  end
end
