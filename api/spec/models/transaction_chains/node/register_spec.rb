# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Node::Register do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def build_node(role: :node)
    Node.new(
      location: SpecSeed.location,
      role: role,
      hypervisor_type: %i[node storage].include?(role) ? :vpsadminos : nil,
      name: "register-#{role}-#{SecureRandom.hex(3)}",
      ip_addr: "198.51.100.#{(Node.maximum(:id).to_i % 200) + 20}",
      max_vps: %i[node storage].include?(role) ? 10 : nil,
      cpus: 4,
      total_memory: 4096,
      total_swap: 1024
    )
  end

  def stub_reservation_range(range = 10_000...10_004)
    allow(described_class).to receive(:new).and_wrap_original do |method|
      method.call.tap do |chain|
        allow(chain).to receive(:reservation_port_range).and_return(range)
      end
    end
  end

  it 'saves and locks a node registration with deterministic port reservations' do
    stub_reservation_range
    node = build_node(role: :node)

    chain, = described_class.fire(node, {})
    reservations = node.port_reservations.order(:port)

    expect(node).to be_persisted
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Node', node.id]
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Node', node.id])
    expect(reservations.pluck(:port)).to eq((10_000...10_004).to_a)

    confirmations = confirmations_for(chain)
    expect(confirmations.any? do |row|
      row.class_name == 'Node' &&
        row.row_pks == { 'id' => node.id } &&
        row.confirm_type == 'just_create_type'
    end).to be(true)
    reservations.each do |reservation|
      expect(confirmations.any? do |row|
        row.class_name == 'PortReservation' &&
          row.row_pks == { 'id' => reservation.id } &&
          row.confirm_type == 'just_create_type'
      end).to be(true)
    end
  end

  it 'reserves ports for storage nodes' do
    stub_reservation_range(11_000...11_003)
    node = build_node(role: :storage)

    described_class.fire(node, {})

    expect(node.port_reservations.order(:port).pluck(:port)).to eq([11_000, 11_001, 11_002])
  end

  it 'does not reserve ports for non-storage infrastructure roles' do
    node = build_node(role: :mailer)

    described_class.fire(node, {})

    expect(node.port_reservations).to be_empty
  end

  it 'creates an active maintenance lock when requested' do
    stub_reservation_range
    node = build_node(role: :node)

    described_class.fire(node, { maintenance: true })

    lock = MaintenanceLock.find_by!(class_name: 'Node', row_id: node.id)
    expect(lock).to be_active
    expect(lock.reason).to eq('Reason not specified')
    expect(node.reload.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
    expect(node.maintenance_lock_reason).to eq('Reason not specified')
  end
end
