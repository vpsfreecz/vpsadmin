require 'spec_helper'

RSpec.describe VpsIncidentSummary do
  before { install_incident_policy_fixture }

  def member(vps, time)
    IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'Source', text: 'Source', detected_at: time,
                           source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
  end

  it 'batches policy rows and threshold aggregates independently of VPS count, with filter/count parity' do
    vpses = Array.new(3) { build_standalone_vps_fixture.fetch(:vps) }
    now = Time.now.utc.change(usec: 0)
    vpses.each do |vps|
      5.times { |i| member(vps, now - i) }
    end
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, event|
      queries << event[:sql] if event[:sql].start_with?('SELECT')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      described_class.load(vpses, now:)
      expect(vpses.map(&:incident_warning_count)).to eq([1, 1, 1])
      expect(vpses.map(&:incident_stop_threshold_count)).to eq([0, 0, 0])
    end
    expect(queries.size).to be <= 9
    expect(described_class.filter(Vps.where(id: vpses.map(&:id)), 'warning', now:, policy_key: 'oomd').count).to eq(3)
    expect(described_class.policy_rows(vpses, now:).values.flatten.map { |p| p[:last_incident_at] }).to all(eq(now))
  end

  %i[queued rollbacking failed fatal resolved].each do |state|
    it "keeps summaries valid while an ownership transfer is #{state}" do
      vps = build_standalone_vps_fixture.fetch(:vps)
      chain = TransactionChains::Vps::Update.create!(name: 'update', state:, user: SpecSeed.admin, size: 1)
      epoch = Time.now.utc.change(usec: 0) - 60
      vps.update_columns(incident_owner_transfer_chain_id: chain.id, incident_accounting_since: epoch)
      expect { described_class.load([vps]) }.not_to raise_error
      expect(vps.incident_summary).to include(incident_accounting_since: epoch, incident_warning_count: 0)
    end
  end

  it 'uses only a confirmed successful Chown finish as the virtual owner epoch' do
    vps = build_standalone_vps_fixture.fetch(:vps)
    now = Time.now.utc.change(usec: 0)
    member(vps, now - 1)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :done, user: SpecSeed.admin, size: 1)
    transaction = Transaction.create!(transaction_chain: chain, handle: 3041, node: vps.node, queue: 'vps')
    transaction.update_columns(done: 1, status: 1, finished_at: now)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    vps.vps_incident_policies.create!(policy_key: 'oomd', last_warning_at: now - 30)
    described_class.load([vps], now:)
    expect(vps.incident_summary).to include(incident_accounting_since: now, incident_warning_count: 0)
    expect(described_class.policy_rows([vps], now:).fetch(vps.id).sole).to include(count_30d: 0, last_warning_at: nil)
    transaction.update_columns(status: 0)
    described_class.load([vps], now:)
    expect(vps.incident_accounting_since).to be_nil
  end
end
