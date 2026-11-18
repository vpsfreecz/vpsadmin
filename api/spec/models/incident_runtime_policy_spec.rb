require 'spec_helper'

RSpec.describe IncidentEscalation do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:now) { Time.now.utc.change(usec: 0) }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { travel_to(now) { example.run } }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
  end

  def rules(*entries)
    configured = entries.to_h do |key, selector, options|
      options ||= {}
      builder = described_class::RuleBuilder.new(key)
      builder.labels en: "Policy #{key}", cs: "Pravidlo #{key}"
      builder.limits warning: options.fetch(:warning, 1), stop: options.fetch(:stop, 2)
      builder.applies_if(&selector) if selector
      builder.suppress_actions(options.fetch(:suppressed, false))
      rule = builder.build
      SysConfig.create!(category: rule.category, name: 'mode', value: options.fetch(:mode, 'enforce'), data_type: 'String')
      [key, rule]
    end
    stub_const('IncidentEscalation::RULES', configured.freeze)
  end

  def arrive(time = now, action: 'restart')
    VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action:, time:, now:)
  end

  it 'captures lexical isolated outcomes on the same source before effects and counts only saved membership' do
    calls = []
    rules(['z_match', lambda { |ctx|
      calls << ['z', ctx]
      true
    }],
          ['a_skip', lambda { |ctx|
            calls << ['a', ctx]
            false
          }],
          ['m_error', lambda { |_ctx|
            calls << ['m', nil]
            raise 'private site data'
          }],
          ['n_always', nil])
    report = nil
    expect { report = arrive }.to output(/automatic actions are disabled/).to_stderr
    expect(calls.map(&:first)).to eq(%w[a m z])
    ctx = calls.last.last
    expect(ctx).to be_frozen
    expect(ctx.owner).to be_frozen
    expect { ctx.owner[:id] = 0 }.to raise_error(FrozenError)
    expect(ctx).to have_attributes(count_7d: 0, count_30d: 0, policy_key: 'z_match')
    outcomes = report.incident_policy_evaluations.order(:policy_key)
    expect(outcomes.map { |e| [e.policy_key, e.matched, e.state] }).to eq([
                                                                            ['a_skip', false, 'skipped'], ['m_error', nil, 'error'], ['n_always', true, 'recorded'], ['z_match', true, 'recorded']
                                                                          ])
    expect(outcomes.find_by!(policy_key: 'z_match').snapshot['context']).to include('count_7d' => 1, 'count_30d' => 1)
    expect(outcomes.to_json).not_to include('private site data')
    expect(vps.vps_incident_actions.pluck(:policy_key)).to contain_exactly('z_match', 'n_always')
    expect(ObjectHistory.where(tracked_object: vps, event_type: 'restart').count).to eq(1)
    expect(MailLog.where(mail_template: MailTemplate.find_by!(name: 'vps_incident_report'), user: vps.user).count).to eq(1)
    expect(described_class.new(vps, policy_key: 'a_skip', now:).counts).to eq([0, 0])
  end

  it 'does not rerun selectors on duplicate delivery, reads, scheduler, retries or changed declarations' do
    calls = 0
    rules(['chosen', lambda { |_ctx|
      calls += 1
      true
    }, { warning: 5, stop: 10 }])
    report = arrive
    snapshot = report.incident_policy_evaluations.sole.attributes
    arrive
    VpsIncidentSummary.load([vps], now:)
    described_class.process!(vps, now: now + 1)
    stub_const('IncidentEscalation::RULES', {})
    arrive
    described_class.process!(vps, now: now + 2)
    expect(calls).to eq(1)
    expect(report.incident_policy_evaluations.sole.attributes).to eq(snapshot)
    expect(IncidentReport.ordinary.where(vps:).count).to eq(1)
  end

  it 'matches late/future and manual creations once but never acts on old events or notices' do
    calls = 0
    rules(['chosen', lambda { |_ctx|
      calls += 1
      true
    }])
    late = arrive(now - described_class::DAY - 1)
    future = arrive(now + 1)
    expect([late, future].map { |r| r.incident_policy_evaluations.sole.state }).to eq(%w[audit_only audit_only])
    expect(described_class.new(vps, policy_key: 'chosen', now:).counts).to eq([1, 1])
    expect(described_class.new(vps, policy_key: 'chosen', now: now + 2).counts).to eq([2, 2])
    manual = IncidentReport.create!(user: vps.user, vps:, codename: 'mail_abuse', subject: 'Manual', text: 'Manual', detected_at: now - described_class::DAY - 1)
    vps.update!(incident_accounting_since: now)
    prior = arrive(now - 1)
    expect(prior.incident_policy_evaluations.sole.matched).to be(false)
    notice = IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'Notice', text: 'Notice', detected_at: now,
                                    source_kind: 'incident_policy_notice')
    described_class.process!(vps, now: now + 2)
    expect(calls).to eq(3)
    expect(manual.incident_policy_evaluations.sole.matched).to be(true)
    expect(notice.incident_policy_evaluations).to be_empty
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'retains membership on invalid effective configuration and isolates it from another policy' do
    rules(['broken', nil], ['valid', nil])
    vps.vps_incident_policies.create!(policy_key: 'broken', warning_limit_override: 1, stop_limit_override: 2)
    vps.vps_incident_policies.find_by!(policy_key: 'broken').update_columns(warning_limit_override: 3)
    report = nil
    expect { report = arrive }.to output(/automatic actions are disabled/).to_stderr
    expect(report.incident_policy_evaluations.find_by!(policy_key: 'broken')).to have_attributes(matched: true, state: 'error')
    expect(described_class.new(vps, policy_key: 'broken', now:).counts).to eq([1, 1])
    expect(vps.vps_incident_actions.pluck(:policy_key)).to eq(['valid'])
    rows = VpsIncidentSummary.policy_rows([vps], now:).fetch(vps.id)
    expect(rows.find { |r| r[:key] == 'broken' }).to include(configuration_valid: false, warning_limit: nil, status: nil)
  end

  it 'groups two stop candidates into one normal physical chain with independent confirmed notices and no replay' do
    rules(['zeta', nil, { warning: 1, stop: 1 }], ['alpha', nil, { warning: 1, stop: 1 }])
    report = arrive
    actions = vps.vps_incident_actions.order(:policy_key).to_a
    owner, follower = actions
    expect(actions.map(&:policy_key)).to eq(%w[alpha zeta])
    expect(actions.map(&:state)).to eq(%w[queued queued])
    expect(follower.stop_owner_action_id).to eq(owner.id)
    expect(actions.map(&:transaction_chain_id).uniq.size).to eq(1)
    chain = owner.transaction_chain
    expect(chain.transactions.where(handle: Transactions::Vps::Stop.t_type).count).to eq(1)
    expect(report.incident_policy_evaluations.pluck(:state)).to eq(%w[recorded recorded])
    stop = chain.transactions.find_by!(handle: Transactions::Vps::Stop.t_type)
    stop.update_columns(done: 1, status: 1, finished_at: now + 2)
    chain.update!(state: :done)
    expect { described_class.process!(vps, now: now + 3) }.not_to(change { Transaction.where(handle: Transactions::Vps::Stop.t_type).count })
    expect(actions.map { |a| a.reload.state }).to eq(%w[completed completed])
    expect(actions.map(&:notice_incident_report_id).uniq.size).to eq(2)
    expect(vps.reload.incident_last_stop_at).to eq(now + 2)
    expect(actions.map { |a| a.notice_incident_report.notice_kind }).to eq(%w[stop_completed stop_completed])
  end

  %i[failed fatal].each do |state|
    it "keeps one physical exclusion for a #{state} chain and never elects a follower to retry it" do
      rules(['alpha', nil, { warning: 1, stop: 1 }], ['zeta', nil, { warning: 1, stop: 1 }])
      arrive
      action = vps.vps_incident_actions.order(:id).first
      action.transaction_chain.update!(state:)
      expect { described_class.process!(vps, now: now + 1) }.not_to(change { Transaction.where(handle: Transactions::Vps::Stop.t_type).count })
      expect(vps.vps_incident_actions.pluck(:state).uniq).to eq([state == :failed ? 'failed' : 'uncertain'])
      expect { arrive(now - 1) }.not_to(change { Transaction.where(handle: Transactions::Vps::Stop.t_type).count })
      expect(vps.vps_incident_actions.where(kind: 'stop').count).to eq(2)
    end
  end

  it 'revalidates each stop candidate independently and picks the remaining eligible owner' do
    rules(['alpha', nil, { warning: 1, stop: 1 }], ['zeta', nil, { warning: 1, stop: 1 }])
    allow(described_class).to receive(:process!)
    arrive
    SysConfig.find_by!(category: 'incident_policy_alpha', name: 'mode').update!(value: 'observe')
    described_class.new(vps, now:).dispatch_stop_groups!
    expect(vps.vps_incident_actions.find_by!(policy_key: 'alpha')).to have_attributes(state: 'suppressed', transaction_chain_id: nil)
    expect(vps.vps_incident_actions.find_by!(policy_key: 'zeta')).to have_attributes(state: 'queued', stop_owner_action_id: nil)
  end

  it 'keeps counts under declared suppression and warnings under shared exemption' do
    rules(['silent', nil, { suppressed: true }], ['visible', nil, { warning: 1, stop: 1 }])
    vps.update!(incident_enforcement_enabled: false)
    arrive
    expect(vps.vps_incident_actions.pluck(:policy_key, :kind)).to eq([%w[visible warning]])
    expect(described_class.new(vps, policy_key: 'silent', now:).counts).to eq([1, 1])
  end

  it 'uses explicit VPS then global then declared limits without resetting shared permission' do
    rules(['chosen', nil, { warning: 5, stop: 10 }])
    SysConfig.create!(category: 'incident_policy_chosen', name: 'warning_limit', value: 4, data_type: 'Integer')
    vps.update!(incident_enforcement_enabled: false)
    described_class.update_policy!(vps, 'chosen', warning_limit_override: 3, stop_limit_override: 6)
    expect(described_class.new(vps, policy_key: 'chosen', now:).effective_result(described_class.rule('chosen').base)).to include('warning_limit' => 3, 'stop_limit' => 6)
    described_class.update_policy!(vps, 'chosen', warning_limit_override: nil, stop_limit_override: nil)
    expect(VpsIncidentSummary.policy_rows([vps], now:).fetch(vps.id).sole).to include(warning_limit: 4, stop_limit: 10)
    expect(vps.reload.incident_enforcement_enabled).to be(false)
  end

  it 'keeps a completed group recoverable after trigger deletion and registry removal without another chain' do
    rules(['alpha', nil, { warning: 1, stop: 1 }], ['zeta', nil, { warning: 1, stop: 1 }])
    report = arrive
    actions = vps.vps_incident_actions.order(:policy_key).to_a
    original = actions.map(&:contributor_snapshot)
    chain = actions.first.transaction_chain
    report.destroy!
    stub_const('IncidentEscalation::RULES', {})
    stop = chain.transactions.find_by!(handle: Transactions::Vps::Stop.t_type)
    stop.update_columns(done: 1, status: 1, finished_at: now + 2)
    chain.update!(state: :done)
    expect { described_class.process!(vps, now: now + 3) }.not_to(change { Transaction.where(handle: Transactions::Vps::Stop.t_type).count })
    actions.each do |action|
      expect(action.reload).to have_attributes(state: 'completed', mail_state: 'queued')
      expect(action.notice_incident_report).to have_attributes(notice_kind: 'stop_completed', trigger_incident_report_id: nil)
      expect(action.notice_incident_report.subject).to include("Policy #{action.policy_key}")
    end
    expect(actions.map(&:contributor_snapshot)).to eq(original)
    expect(vps.reload.incident_last_stop_at).to eq(now + 2)
  end

  it 'rejects nonboolean selectors and suppresses stale undispatched decisions without invoking selectors again' do
    calls = 0
    selector = lambda do |_ctx|
      calls += 1
      true
    end
    rules(['invalid', ->(_ctx) { :yes }], ['valid', selector])
    allow(described_class).to receive(:process!)
    report = nil
    expect { report = arrive }.to output(/automatic actions are disabled/).to_stderr
    expect(report.incident_policy_evaluations.find_by!(policy_key: 'invalid')).to have_attributes(matched: nil, state: 'error')
    action = vps.vps_incident_actions.sole
    expect(action.kind).to eq('warning')
    allow(described_class).to receive(:policy_digest).and_return('changed-file-bytes')
    described_class.new(vps, policy_key: 'valid', now:).dispatch_actions!
    expect(action.reload).to have_attributes(state: 'suppressed', mail_state: 'suppressed', mail_log_id: nil)
    expect(calls).to eq(1)
  end
end
