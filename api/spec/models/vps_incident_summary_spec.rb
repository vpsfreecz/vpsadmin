require 'spec_helper'

RSpec.describe VpsIncidentSummary do
  it 'loads a batch with a fixed number of queries and returns filter/count parity' do
    vpses = Array.new(3) { build_standalone_vps_fixture.fetch(:vps) }
    now = Time.now.utc.change(usec: 0)
    vpses.each do |vps|
      4.times do |i|
        IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'OOM', text: 'OOM', detected_at: now - i,
                               source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
      end
    end
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, event|
      queries << event[:sql] if event[:sql].start_with?('SELECT')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      described_class.load(vpses, now:)
      vpses.each { |vps| expect(vps.incident_count_7d).to eq(4) }
    end
    expect(queries.size).to be <= 6
    expect(described_class.filter(Vps.where(id: vpses.map(&:id)), 'near_limit', now:).count).to eq(3)
    expect(vpses.map(&:incident_last_incident_at)).to all(eq(now))
  end

  %i[queued rollbacking failed fatal resolved].each do |state|
    it "keeps summaries valid while an ownership transfer is #{state}" do
      vps = build_standalone_vps_fixture.fetch(:vps)
      chain = TransactionChains::Vps::Update.create!(name: 'update', state:, user: SpecSeed.admin, size: 1)
      epoch = Time.now.utc.change(usec: 0) - 60
      vps.update_columns(incident_owner_transfer_chain_id: chain.id, incident_accounting_since: epoch)

      expect { described_class.load([vps]) }.not_to raise_error
      expect(vps.incident_summary).to include(incident_accounting_since: epoch, incident_count_30d: 0)
    end
  end

  it 'uses only a confirmed successful Chown finish as the virtual ownership epoch' do
    vps = build_standalone_vps_fixture.fetch(:vps)
    now = Time.now.utc.change(usec: 0)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :done, user: SpecSeed.admin, size: 1)
    transaction = Transaction.create!(transaction_chain: chain, handle: 3041, node: vps.node, queue: 'vps')
    transaction.update_columns(done: 1, status: 1, finished_at: now)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now - 30)
    IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'Prior epoch', text: 'Prior epoch', detected_at: now - 1,
                           source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)

    described_class.load([vps], now:)
    expect(vps.incident_summary).to include(incident_accounting_since: now, incident_count_30d: 0, incident_last_warning_at: nil)
    transaction.update_columns(status: 0)
    described_class.load([vps], now:)
    expect(vps.incident_summary).to include(incident_accounting_since: nil, incident_count_30d: 1, incident_last_warning_at: now - 30)
  end
end
