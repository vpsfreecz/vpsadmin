# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::NetAccounting do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:time) { Time.utc(2026, 4, 6, 10, 30, 0) }

  def accounting_payload(netif, at: time, bytes_in: 100, bytes_out: 200,
                         packets_in: 10, packets_out: 20)
    {
      'id' => netif.id,
      'user_id' => netif.vps.user_id,
      'time' => at.to_i,
      'bytes_in' => bytes_in,
      'bytes_out' => bytes_out,
      'packets_in' => packets_in,
      'packets_out' => packets_out
    }
  end

  describe '#save_accounting' do
    it 'accumulates daily, monthly, and yearly counters for the same buckets' do
      netif = create_netif_vps_fixture!(node:).fetch(:netif)
      later = time + 120

      supervisor.send(:save_accounting, [accounting_payload(netif)])
      supervisor.send(
        :save_accounting,
        [
          accounting_payload(
            netif,
            at: later,
            bytes_in: 300,
            bytes_out: 400,
            packets_in: 30,
            packets_out: 40
          )
        ]
      )

      daily = NetworkInterfaceDailyAccounting.find_by!(
        network_interface_id: netif.id,
        user_id: netif.vps.user_id,
        year: time.year,
        month: time.month,
        day: time.day
      )
      monthly = NetworkInterfaceMonthlyAccounting.find_by!(
        network_interface_id: netif.id,
        user_id: netif.vps.user_id,
        year: time.year,
        month: time.month
      )
      yearly = NetworkInterfaceYearlyAccounting.find_by!(
        network_interface_id: netif.id,
        user_id: netif.vps.user_id,
        year: time.year
      )

      [daily, monthly, yearly].each do |row|
        expect(row.bytes_in).to eq(400)
        expect(row.bytes_out).to eq(600)
        expect(row.packets_in).to eq(40)
        expect(row.packets_out).to eq(60)
        expect(row.created_at).to eq(time)
        expect(row.updated_at).to eq(later)
      end
    end

    it 'ignores foreign interfaces and derives the user from the local interface owner' do
      local_netif = create_netif_vps_fixture!(node:, user: SpecSeed.user).fetch(:netif)
      foreign_netif = create_netif_vps_fixture!(node: SpecSeed.other_node, user: SpecSeed.other_user).fetch(:netif)
      forged_user_id = SpecSeed.other_user.id

      supervisor.send(
        :save_accounting,
        [
          accounting_payload(local_netif).merge('user_id' => forged_user_id),
          accounting_payload(foreign_netif)
        ]
      )

      expect(
        NetworkInterfaceMonthlyAccounting.where(
          network_interface: foreign_netif,
          user_id: foreign_netif.vps.user_id
        )
      ).not_to exist
      expect(
        NetworkInterfaceMonthlyAccounting.where(
          network_interface: local_netif,
          user_id: forged_user_id
        )
      ).not_to exist

      monthly = NetworkInterfaceMonthlyAccounting.find_by!(
        network_interface: local_netif,
        user_id: local_netif.vps.user_id,
        year: time.year,
        month: time.month
      )
      expect(monthly.bytes_in).to eq(100)
      expect(monthly.bytes_out).to eq(200)
    end
  end
end
