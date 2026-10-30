require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::VPS do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  before { header 'Accept', 'application/json' }

  def update_settings(settings)
    settings = settings.merge(incident_policy: 'oomd') if settings.keys.map(&:to_s).intersect?(IncidentEscalation::SETTINGS)
    put vpath("/vpses/#{vps.id}"), JSON.dump(vps: settings), 'CONTENT_TYPE' => 'application/json'
  end

  it 'shows owner summaries but hides raw overrides and rejects owner writes' do
    as(vps.user) { get vpath("/vpses/#{vps.id}") }
    expect(json['status']).to be(true), json.inspect
    row = json.fetch('response').fetch('vps')
    expect(row).to include('incident_count_7d' => 0, 'incident_mode' => 'observe', 'incident_action_state' => 'none')
    expect(row).not_to have_key('incident_warning_limit_override')
    as(vps.user) { update_settings(incident_enforcement_enabled: false) }
    expect(vps.reload.incident_enforcement_enabled).to be(true)
  end

  it 'allows atomic admin changes and explicit null reset with synchronous ack' do
    unlock_transaction_signer!
    as(SpecSeed.admin) { update_settings(incident_warning_limit_override: 12, incident_stop_limit_override: 15) }
    expect(json['status']).to be(true), json.inspect
    expect(vps.reload).to have_attributes(incident_warning_limit_override: 12, incident_stop_limit_override: 15)
    as(SpecSeed.admin) { update_settings(incident_warning_limit_override: nil, incident_stop_limit_override: nil) }
    expect(json['status']).to be(true), json.inspect
    expect(vps.reload).to have_attributes(incident_warning_limit_override: nil, incident_stop_limit_override: nil)
  end

  it 'rejects an invalid final pair and preserves the prior settings' do
    unlock_transaction_signer!
    as(SpecSeed.admin) { update_settings(incident_warning_limit_override: 11) }
    expect(json['status']).to be(false)
    expect(vps.reload.incident_warning_limit_override).to be_nil
  end

  it 'does not expose another owners summary and scopes filters before pagination' do
    as(SpecSeed.other_user) { get vpath("/vpses/#{vps.id}") }
    expect(json['status']).to be(false)
    4.times do |i|
      IncidentReport.create!(vps:, user: vps.user, codename: 'oomd', subject: 'OOM', text: 'OOM', detected_at: Time.now - i,
                             source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
    end
    as(vps.user) { get vpath('/vpses'), vps: { incident_status: 'near_limit' } }
    expect(json['status']).to be(true), json.inspect
    rows = json.fetch('response').fetch('vpses')
    expect(rows.map { |row| row['id'] }).to include(vps.id)
    expect(rows.find { |row| row['id'] == vps.id }['incident_count_7d']).to eq(4)
    as(SpecSeed.other_user) { get vpath('/vpses'), vps: { incident_status: 'near_limit' } }
    expect(json.fetch('response').fetch('vpses').map { |row| row['id'] }).not_to include(vps.id)
  end

  it 'rejects mixed OOM settings and other mutations before preparing any effects' do
    original = vps.attributes
    chains = TransactionChain.count
    transactions = Transaction.count
    audit = PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: vps.vps_incident_policies.find_by(incident_type: 'oomd')&.id).count
    [{ hostname: 'mixed-change' }, { cpu_limit: 50 }, { object_state: 'suspended' }].each do |other|
      as(SpecSeed.admin) { update_settings(other.merge(incident_warning_limit_override: 8)) }
      expect(json['status']).to be(false)
      expect(json['message']).to include('separately')
      expect(vps.reload.attributes).to eq(original)
    end
    expect(TransactionChain.count).to eq(chains)
    expect(Transaction.count).to eq(transactions)
    expect(PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: vps.vps_incident_policies.find_by(incident_type: 'oomd')&.id).count).to eq(audit)
  end

  it 'audits isolated settings synchronously and rejects conflicting later global defaults' do
    unlock_transaction_signer!
    audit = PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: vps.vps_incident_policies.find_by(incident_type: 'oomd')&.id).count
    as(SpecSeed.admin) { update_settings(incident_warning_limit_override: 8) }
    expect(json['status']).to be(true), json.inspect
    expect(vps.reload.incident_warning_limit_override).to eq(8)
    expect(PaperTrail::Version.where(item_type: 'VpsIncidentPolicy', item_id: vps.vps_incident_policies.find_by(incident_type: 'oomd')&.id).count).to eq(audit + 1)
    as(SpecSeed.admin) do
      put vpath('/system_configs/incident_policy_oomd/stop_limit'), JSON.dump(system_config: { value: 6 }),
          'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(false)
    expect(SysConfig.get(:incident_policy_oomd, :stop_limit)).to eq(10)
    expect(vps.reload.incident_warning_limit_override).to eq(8)
  end

  it 'preserves asynchronous behavior for ordinary non-OOM updates' do
    unlock_transaction_signer!
    as(SpecSeed.admin) { update_settings(hostname: 'ordinary-update') }
    expect(json['status']).to be(true), json.inspect
    chain = TransactionChain.order(:id).last
    expect(chain.transactions.pluck(:handle)).to include(Transactions::Vps::Hostname.t_type)
  end

  it 'rejects unknown, blank and null selectors without effects' do
    original = vps.attributes
    ['unknown', '', nil].each do |type|
      as(SpecSeed.admin) do
        get vpath("/vpses/#{vps.id}"), vps: { incident_policy: type }
      end
      expect(json['status']).to be(false), json.inspect
      as(SpecSeed.admin) do
        put vpath("/vpses/#{vps.id}"), JSON.dump(vps: { incident_policy: type, incident_enforcement_enabled: false }),
            'CONTENT_TYPE' => 'application/json'
      end
      expect(json['status']).to be(false), json.inspect
      expect(vps.reload.attributes).to eq(original)
    end
  end

  it 'requires an explicit selector and a setting for isolated incident writes' do
    [{ incident_policy: 'oomd' }, { incident_enforcement_enabled: false }].each do |settings|
      as(SpecSeed.admin) do
        put vpath("/vpses/#{vps.id}"), JSON.dump(vps: settings), 'CONTENT_TYPE' => 'application/json'
      end
      expect(json['status']).to be(false), json.inspect
      expect(vps.reload.incident_enforcement_enabled).to be(true)
    end
    expect(vps.vps_incident_policies).to be_empty
  end

  it 'returns the selected registered label and does not create policy rows on reads' do
    as(vps.user) do
      header 'Accept-Language', 'cs'
      get vpath("/vpses/#{vps.id}"), vps: { incident_policy: 'oomd' }
    end
    expect(json['status']).to be(true), json.inspect
    expect(json.fetch('response').fetch('vps')).to include('incident_policy' => 'oomd', 'incident_count_7d' => 0)
    expect(vps.vps_incident_policies).to be_empty
  end

  describe 'confirmed timestamps before scheduler persistence' do
    let(:now) { Time.now.utc.change(usec: 0) }

    def confirmed_transaction(chain_class, handle, finished_at)
      chain = chain_class.create!(name: 'spec-confirmed', state: :done, user: SpecSeed.admin, size: 1)
      transaction = Transaction.create!(transaction_chain: chain, handle:, node: vps.node, queue: 'vps')
      transaction.update_columns(done: 1, status: 1, finished_at:)
      chain
    end

    def read_show_and_index
      as(vps.user) { get vpath("/vpses/#{vps.id}") }
      expect(json['status']).to be(true), json.inspect
      yield json.fetch('response').fetch('vps')
      as(vps.user) { get vpath('/vpses'), vps: { incident_policy: 'oomd' } }
      expect(json['status']).to be(true), json.inspect
      yield json.fetch('response').fetch('vpses').find { |row| row.fetch('id') == vps.id }
    end

    it 'serializes the confirmed stop time with its cooldown before reconciliation' do
      finished = now - 60
      chain = confirmed_transaction(TransactionChains::Vps::Stop, 1002, finished)
      incident = IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'Stop trigger', text: 'Stop trigger', detected_at: finished)
      vps.vps_incident_actions.create!(user: vps.user, incident_report: incident, incident_type: 'oomd', kind: 'stop',
                                       state: 'queued', transaction_chain: chain, incident_count_7d: 10, incident_count_30d: 10)

      read_show_and_index do |row|
        expect(Time.parse(row.fetch('incident_last_stop_at'))).to eq(finished)
        expect(Time.parse(row.fetch('incident_next_stop_allowed_at'))).to eq(finished + IncidentEscalation::DAY)
        expect(row.fetch('incident_action_state')).to eq('none')
      end
      expect(vps.reload[:incident_last_stop_at]).to be_nil
      VpsIncidentSummary.load([vps], now:)
      expect(vps.incident_last_stop_at).to eq(finished)
      IncidentEscalation.new(vps, now:).reconcile_actions!
      expect(vps[:incident_last_stop_at]).to eq(finished)
    end

    it 'serializes the confirmed ownership epoch and retains the physical stop cooldown' do
      finished = now - 60
      stopped = now - 3600
      chain = confirmed_transaction(TransactionChains::Vps::Update, 3041, finished)
      vps.update_columns(incident_owner_transfer_chain_id: chain.id, incident_accounting_since: now - 7200, incident_last_stop_at: stopped)
      vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now - 120)
      IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'Prior epoch', text: 'Prior epoch', detected_at: finished - 1,
                             source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)

      read_show_and_index do |row|
        expect(Time.parse(row.fetch('incident_accounting_since'))).to eq(finished)
        expect(Time.parse(row.fetch('incident_last_stop_at'))).to eq(stopped)
        expect(Time.parse(row.fetch('incident_next_stop_allowed_at'))).to eq(stopped + IncidentEscalation::DAY)
        expect(row).to include('incident_count_7d' => 0, 'incident_count_30d' => 0, 'incident_last_warning_at' => nil)
      end
      expect(vps.reload[:incident_accounting_since]).to eq(now - 7200)
      VpsIncidentSummary.load([vps], now:)
      expect(vps.incident_accounting_since).to eq(finished)
      evaluator = IncidentEscalation.new(vps, now:)
      expect(evaluator.counts).to eq([1, 1])
      evaluator.reconcile_transfer!
      expect(vps[:incident_accounting_since]).to eq(finished)
      expect(evaluator.counts).to eq([0, 0])
      expect(vps[:incident_last_stop_at]).to eq(stopped)
    end
  end
end
