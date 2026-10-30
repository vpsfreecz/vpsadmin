require 'spec_helper'

RSpec.describe IncidentEscalation do
  let(:now) { Time.now.utc.change(usec: 0) }
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
    ensure_alert_mail_templates!
    ensure_mailer_available!
  end

  def incident(time = now, **attrs)
    IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'OOM', text: 'Resource pressure',
                           detected_at: time, source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id, **attrs)
  end

  def evaluate(report)
    described_class.new(vps, now:).decide!(report)
  end

  it 'warns on 4 to 5 and stops on 9 to 10, superseding warnings' do
    reports = Array.new(4) { |i| incident(now - (60 * (i + 1))) }
    evaluate(reports.last)
    expect(vps.vps_incident_actions).to be_empty
    evaluate(incident)
    expect(vps.vps_incident_actions.last.kind).to eq('warning')
    vps.vps_incident_actions.update_all(state: 'completed', mail_state: 'sent')
    vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now)
    4.times { |i| incident(now - 400 - i) }
    evaluate(incident(now - 1))
    expect(vps.vps_incident_actions.last.kind).to eq('stop')
  end

  it 'uses open lower rolling boundaries and excludes manual, future and previous-owner events' do
    incident(now - (7 * described_class::DAY))
    incident(now - (30 * described_class::DAY))
    incident(now + 1)
    incident(now - 1, user: SpecSeed.other_user)
    incident(now - 1, source_key: nil)
    incident(now - 1)
    expect(described_class.new(vps, now:).counts).to eq([1, 2])
  end

  it 'never decides on old or future events, even while counts meet limits' do
    10.times { |i| incident(now - 100 - i) }
    evaluate(incident(now - described_class::DAY - 1))
    evaluate(incident(now + 1))
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'counts cooldown events but requires the next event after the cooldown' do
    vps.update!(incident_last_stop_at: now - described_class::DAY)
    10.times { |i| incident(now - 100 - i) }
    evaluate(incident(now - 1))
    expect(vps.vps_incident_actions.where(kind: 'stop')).to be_empty
    evaluate(incident)
    expect(vps.vps_incident_actions.last.kind).to eq('stop')
  end

  it 'keeps warnings and counts under exemption and notification mode; observation never dispatches' do
    vps.update!(incident_enforcement_enabled: false)
    10.times { |i| incident(now - 100 - i) }
    evaluate(incident)
    expect(vps.vps_incident_actions.last.kind).to eq('warning')
    VpsIncidentAction.where(vps_id: vps.id).delete_all
    vps.reload
    SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'observe')
    evaluate(incident)
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'deduplicates ingestion before existing or policy mail chains' do
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([instance_double(TransactionChain, id: 123), nil])
    2.times { VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action: 'restart', time: now) }
    expect(IncidentReport.where(vps: vps).count).to eq(1)
    expect(TransactionChains::IncidentReport::New).to have_received(:fire).once
  end

  it 'defers ResourceLocked with one durable decision and prepares only one stop' do
    10.times { |i| incident(now - i - 1) }
    evaluate(incident)
    allow(TransactionChains::Vps::Stop).to receive(:fire).and_raise(ResourceLocked.new(vps, 'busy'))
    policy = described_class.new(vps, now:)
    policy.dispatch_actions!
    action = vps.vps_incident_actions.last
    expect(action).to have_attributes(state: 'pending', transaction_chain_id: nil)
    allow(TransactionChains::Vps::Stop).to receive(:fire).and_call_original
    described_class.new(vps, now: now + 61).dispatch_actions!
    expect(action.reload.state).to eq('queued')
    evaluate(incident(now + 1))
    expect(vps.vps_incident_actions.count).to eq(1)
  end

  it 'starts cooldown from confirmed physical completion and retries mail without a second stop' do
    10.times { |i| incident(now - i - 1) }
    evaluate(incident)
    described_class.new(vps, now:).dispatch_actions!
    action = vps.vps_incident_actions.last
    stop = action.transaction_chain.transactions.find_by!(handle: 1002)
    stop.update_columns(done: :done, status: 1, finished_at: now + 2)
    action.transaction_chain.update!(state: :done)
    policy = described_class.new(vps, now: now + 3)
    policy.reconcile_actions!
    expect(vps.reload.incident_last_stop_at).to eq(now + 2)
    expect(action.reload.state).to eq('completed')
    policy.dispatch_actions!
    expect(action.reload.mail_state).to eq('queued')
    mail = action.mail_log.mail_transaction
    mail.update_columns(done: :done, status: 0, finished_at: now + 4)
    policy.reconcile_actions!
    expect(action.reload.mail_state).to eq('failed')
    expect { described_class.new(vps, now: now + 600).dispatch_actions! }.not_to(change { Transaction.where(handle: 1002).count })
    expect(action.reload.mail_log.message_id).to eq(action.message_id)
  end

  it 'does not automatically repeat failed or uncertain physical stops' do
    10.times { |i| incident(now - i - 1) }
    evaluate(incident)
    policy = described_class.new(vps, now:)
    policy.dispatch_actions!
    action = vps.vps_incident_actions.last
    action.transaction_chain.update!(state: :fatal)
    policy.reconcile_actions!
    expect(action.reload.state).to eq('uncertain')
    expect { policy.dispatch_actions! }.not_to(change { Transaction.where(handle: 1002).count })
  end

  it 'renders current permission and limits with the original decision counts' do
    10.times { |i| incident(now - i - 1) }
    evaluate(incident)
    action = vps.vps_incident_actions.last
    described_class.update_settings!(vps, incident_policy: 'oomd', incident_enforcement_enabled: false, incident_stop_limit_override: 20)
    vars = described_class.new(vps, now:).mail_vars(action)
    expect(vars).to include(stop_enforced: false, stop_limit: 20, incident_count_30d: 11)
  end

  it 'reconciles successful ownership transfer at Chown finish and preserves the stop cooldown' do
    vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now - 1)
    vps.update!(incident_last_stop_at: now - 2)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :queued, user: SpecSeed.admin, size: 1)
    transaction = Transaction.create!(transaction_chain: chain, handle: 3041, node: vps.node, queue: 'vps')
    transaction.update_columns(done: 1, status: 1, finished_at: now)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    policy = described_class.new(vps, now:)
    policy.reconcile_transfer!
    expect(vps.incident_accounting_since).to be_nil
    chain.update!(state: :done)
    policy.reconcile_transfer!
    expect(vps).to have_attributes(incident_accounting_since: now, incident_last_warning_at: nil, incident_last_stop_at: now - 2)
    incident(now - 1)
    expect(policy.counts).to eq([0, 0])
  end

  it 'preserves the accounting epoch and warning when transfer rolls back' do
    vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now - 1)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :failed, user: SpecSeed.admin, size: 1)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    described_class.new(vps, now:).reconcile_transfer!
    expect(vps).to have_attributes(incident_accounting_since: nil, incident_last_warning_at: now - 1, incident_owner_transfer_chain_id: nil)
  end

  it 'allows another warning only on a new incident after 7 days' do
    vps.update!(incident_enforcement_enabled: false)
    vps.vps_incident_policies.create!(incident_type: 'oomd', last_warning_at: now - (7 * described_class::DAY) + 1)
    5.times { |i| incident(now - i - 1) }
    evaluate(incident)
    expect(vps.vps_incident_actions).to be_empty
    described_class.new(vps, now: now + 2).decide!(incident(now + 1))
    expect(vps.vps_incident_actions.last.kind).to eq('warning')
  end

  it 'expires undispatched decisions rather than scheduling a later stop' do
    10.times { |i| incident(now - i - 1) }
    evaluate(incident)
    action = vps.vps_incident_actions.last
    described_class.new(vps, now: now + described_class::DAY + 1).dispatch_actions!
    expect(action.reload.state).to eq('suppressed')
    expect(action.transaction_chain_id).to be_nil
  end

  it 'rejects invalid inherited settings and disables dispatch for invalid stored config' do
    expect { described_class.update_settings!(vps, incident_policy: 'oomd', incident_warning_limit_override: 11) }.to raise_error(ActiveRecord::RecordInvalid)
    SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update_column(:value, 'broken')
    10.times { |i| incident(now - i - 1) }
    expect { evaluate(incident) }.to output(/automatic actions are disabled/).to_stderr
    expect(vps.vps_incident_actions).to be_empty
  end

  it 'prepares a stop when the member disabled ordinary incident mail and durably acknowledges suppression' do
    template = MailTemplate.find_by!(name: 'vps_incident_report')
    UserMailTemplateRecipient.handle_update!(vps.user, template, enabled: false)
    9.times { |i| incident(now - i - 1, notification_processed_at: now) }

    VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action: 'restart', time: now, now:)

    trigger = IncidentReport.find_by!(vps: vps, detected_at: now)
    stop = vps.vps_incident_actions.find_by!(kind: 'stop')
    expect(stop).to have_attributes(state: 'queued')
    expect(stop.transaction_chain.transactions.pluck(:handle)).to include(1002)
    expect(trigger).to have_attributes(notification_processed_at: now, notification_chain_id: nil)
    expect(MailLog.where(mail_template: template)).to be_empty
    UserMailTemplateRecipient.handle_update!(vps.user, template, enabled: true)
    expect { described_class.process!(vps, now: now + 1) }.not_to change(TransactionChain, :count)
    expect(trigger.reload.notification_processed_at).to eq(now)
  end

  it 'rolls back failed ordinary mail preparation without rolling back the stop and retries only that mail' do
    9.times { |i| incident(now - i - 1, notification_processed_at: now) }
    template = MailTemplate.find_by!(name: 'vps_incident_report')
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_wrap_original do |original, report|
      original.call(report)
      raise 'mail preparation failed after creating its chain'
    end

    expect do
      VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps, node: vps.node, action: 'restart', time: now, now:)
    end.to output(/Unable to queue incident.*mail preparation failed/).to_stderr

    trigger = IncidentReport.find_by!(vps: vps, detected_at: now)
    stop = vps.vps_incident_actions.find_by!(kind: 'stop')
    expect(stop.state).to eq('queued')
    expect(trigger).to have_attributes(notification_processed_at: nil, notification_chain_id: nil)
    expect(MailLog.where(mail_template: template)).to be_empty
    stop_id = stop.transaction_chain_id
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_call_original
    described_class.process!(vps, now: now + 1)
    expect(trigger.reload.notification_processed_at).to eq(now + 1)
    expect(trigger.notification_chain_id).to be_present
    expect(stop.reload.transaction_chain_id).to eq(stop_id)
    mail_chain_id = trigger.notification_chain_id
    expect { described_class.process!(vps, now: now + 2) }.not_to change(TransactionChain, :count)
    expect(trigger.reload.notification_chain_id).to eq(mail_chain_id)
  end

  it 'rejects mixed settings in direct update-chain callers without retaining a chain or changes' do
    original = vps.attributes
    expect do
      TransactionChains::Vps::Update.fire(vps, { incident_warning_limit_override: 8, hostname: 'mixed-direct' })
    end.to raise_error(ActiveRecord::RecordInvalid, /separately/)
    expect(vps.reload.attributes).to eq(original)
    expect(TransactionChain.where(name: 'update', user_id: SpecSeed.admin.id)).to be_empty
  end
end
