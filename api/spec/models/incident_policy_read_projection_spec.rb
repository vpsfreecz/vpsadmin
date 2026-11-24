require 'spec_helper'

RSpec.describe IncidentPolicyReadProjection do
  let(:now) { Time.now.utc.change(usec: 0) }
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  before { install_generic_incident_policy_fixture }

  def projection = described_class.new(now:)

  it 'pages VPS/policy pairs in SQL with exact counts, stable ties and empty-page metadata' do
    vpses = Array.new(3) { build_standalone_vps_fixture.fetch(:vps) }
    vpses.each { |item| read_report(item, detected_at: now - 60) }
    result = projection.exposures(limit: 3, sort: 'vps_id')
    expect(result[:meta]).to include(total_count: 6, offset: 0, limit: 3, next_offset: 3, as_of: now)
    expected = vpses.flat_map { |item| %w[category content].map { |key| "#{item.id}:#{key}" } }
    expect(result[:rows].map { |row| row[:id] }).to eq(expected.take(3))
    second = projection.exposures(offset: 3, limit: 3, sort: 'vps_id')
    expect(second[:rows].map { |row| row[:id] }).to eq(expected.drop(3))
    expect(second[:meta][:next_offset]).to be_nil
    expect(projection.exposures(offset: 20)[:meta]).to include(total_count: 6, next_offset: nil)
    expect(projection.exposures(policy_key: 'category', vps_id: vpses.first.id)[:rows].length).to eq(1)
  end

  it 'uses saved matches and strict detection windows plus the evaluation cutoff, never selectors on reads' do
    [now - (30 * 86_400), now - (7 * 86_400), now - 1, now + 1].each do |time|
      read_report(vps, detected_at: time, evaluated_at: now)
    end
    read_report(vps, detected_at: now - 2, evaluated_at: now + 1)
    allow(IncidentEscalation).to receive(:new).and_raise('Read invoked engine')
    allow(IncidentEscalation).to receive(:reconcile!).and_raise('Read mutated state')
    row = projection.exposures(policy_key: 'category')[:rows].sole
    expect(row).to include(count_7d: 1, count_30d: 2, last_incident_at: now - 1, warning_remaining: 1, stop_remaining: 2)
    expect(vps.reload.incident_accounting_since).to be_nil
  end

  it 'preserves owner/transfer boundaries, includes inactive owners and physically stopped VPSes' do
    read_report(vps, detected_at: now - 60)
    vps.user.update_columns(object_state: User.object_states[:suspended])
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :queued, user: SpecSeed.admin, size: 1)
    vps.update_columns(incident_owner_transfer_chain_id: chain.id)
    row = projection.exposures(policy_key: 'category')[:rows].sole
    expect(row).to include(owner_active: false, transfer_pending: true, count_30d: 1)
    vps.update_columns(user_id: SpecSeed.other_user.id)
    expect(projection.exposures[:rows]).to be_empty
    vps.update_columns(user_id: row[:user_id])
    chain.update_columns(state: TransactionChain.states[:done])
    chown = Transaction.create!(transaction_chain: chain, handle: 3041, node: vps.node, queue: 'vps')
    chown.update_columns(done: 1, status: 1, finished_at: now - 30)
    expect(projection.exposures[:rows]).to be_empty
    read_report(vps.reload, detected_at: now - 1)
    expect(projection.exposures[:rows].first).to include(transfer_pending: false, accounting_since: now - 30)
  end

  it 'keeps invalid settings visible with null limits and filters using the selected effective facts' do
    2.times { |i| read_report(vps, detected_at: now - i - 1) }
    SysConfig.find_by!(category: 'incident_policy_category', name: 'mode').update!(value: 'enforce')
    row = projection.exposures(policy_key: 'category')[:rows].sole
    expect(row).to include(status: 'warning', warning_remaining: 0, stop_remaining: 2, warning_permitted: true, stop_enforced: true)
    vps.update_columns(incident_enforcement_enabled: false)
    expect(projection.exposures(stop_enforced: true)[:rows]).to be_empty
    policy = VpsIncidentPolicy.create!(vps:, policy_key: 'category')
    policy.update_columns(warning_limit_override: 5, stop_limit_override: 1)
    invalid = projection.exposures(status: 'invalid')
    expect(invalid[:meta][:total_count]).to eq(1)
    expect(invalid[:rows].sole).to include(configuration_valid: false, warning_limit: nil, status: nil, stop_enforced: nil)
    expect(projection.exposures(status: 'warning')[:rows]).to be_empty
  end

  it 'orders failures ahead of thresholds, and reads shared stop confirmation without reconciling or writing' do
    _, evaluation = read_report(vps, detected_at: now - 60)
    action = read_action(evaluation, state: 'failed')
    row = projection.exposures[:rows].first
    expect(row).to include(outstanding_stop_state: 'failed', outstanding_stop_action_id: action.id)
    chain = read_stop_chain(vps, finished_at: now - 10)
    action.update!(transaction_chain: chain, state: 'queued')
    row = projection.exposures(policy_key: 'category')[:rows].sole
    expect(row).to include(outstanding_stop_state: 'none', last_stop_at: now - 10, next_stop_allowed_at: now - 10 + 86_400,
                           latest_action_state: 'completed', latest_stop_completed_at: now - 10)
    expect(action.reload.state).to eq('queued')
    expect(vps.reload.incident_last_stop_at).to be_nil
  end

  it 'derives uncertain outcomes for finished shared stop chains without successful native evidence, without writes' do
    pending_vps = build_standalone_vps_fixture.fetch(:vps)
    _, pending_evaluation = read_report(pending_vps, detected_at: now - 60)
    pending_chain = read_stop_chain(pending_vps, finished_at: nil)
    pending_chain.update_columns(state: TransactionChain.states[:queued])
    read_action(pending_evaluation, state: 'queued', transaction_chain: pending_chain)

    report, evaluation = read_report(vps, detected_at: now - 60)
    chain = read_stop_chain(vps, finished_at: nil)
    transaction = chain.transactions.find_by!(handle: 1002)
    owner = read_action(evaluation, state: 'queued', transaction_chain: chain)
    follower_evaluation = report.incident_policy_evaluations.find_by!(policy_key: 'content')
    follower = read_action(follower_evaluation, state: 'queued', stop_owner_action: owner)
    allow(IncidentEscalation).to receive(:new).and_raise('Read invoked engine reconciliation')

    assert_uncertain = lambda do
      writes = []
      subscriber = lambda do |_name, _start, _finish, _id, event|
        writes << event[:sql] if event[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE|REPLACE)\b/i)
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        rows = projection.exposures[:rows]
        expect(rows.take(2).map { |row| row[:vps_id] }).to eq([vps.id, vps.id])
        expect(rows.take(2)).to all(include(outstanding_stop_state: 'uncertain', outstanding_stop_action_id: owner.id,
                                            outstanding_stop_chain_id: chain.id, latest_action_state: 'uncertain', latest_stop_completed_at: nil))
        history = projection.history(scope: 'all', vps_id: vps.id, action_state: 'uncertain')
        expect(history[:meta][:total_count]).to eq(2)
        expect(history[:rows].map { |row| row[:id] }).to contain_exactly(evaluation.id, follower_evaluation.id)
        expect(history[:rows]).to all(include(action_state: 'uncertain', physical_stop_action_id: owner.id, stop_completed_at: nil))
        expect(projection.history(scope: 'outstanding', vps_id: vps.id, action_state: 'uncertain')[:meta][:total_count]).to eq(2)
      end
      expect(writes).to be_empty
      expect(owner.reload.state).to eq('queued')
      expect(follower.reload.state).to eq('queued')
      expect(vps.reload.incident_last_stop_at).to be_nil
    end

    transaction.delete
    assert_uncertain.call
    transaction = Transaction.create!(transaction_chain: chain, handle: 1002, node: vps.node, queue: 'vps')
    [
      { done: 1, status: 0, finished_at: now - 10 },
      { done: 0, status: 1, finished_at: nil },
      { done: 1, status: 1, finished_at: nil }
    ].each do |evidence|
      transaction.update_columns(**evidence)
      assert_uncertain.call
    end

    transaction.update_columns(done: 1, status: 1, finished_at: now - 10)
    expect(projection.history(scope: 'all', vps_id: vps.id)[:rows]).to all(include(action_state: 'completed', stop_completed_at: now - 10))
    owner.update_columns(state: 'suppressed')
    expect(projection.history(scope: 'all', vps_id: vps.id)[:rows].find { |row| row[:id] == evaluation.id }[:action_state]).to eq('suppressed')
  end

  it 'retains original history identities, retired keys, missing associations and malformed old snapshot facts' do
    report, evaluation = read_report(vps, detected_at: now - 60)
    IncidentPolicyEvaluation.where(id: evaluation.id).update_all(policy_key: 'retired', snapshot: '{}')
    report.update_columns(vps_id: 987_654_321, user_id: 987_654_321)
    row = projection.history(scope: 'all')[:rows].find { |item| item[:id] == evaluation.id }
    expect(row).to include(policy_key: 'retired', label: 'retired', vps_id: 987_654_321, user_id: 987_654_321,
                           hostname: nil, user_login: nil, count_7d: nil, warning_limit: nil, stop_enforced: nil, threshold_status: nil)
    expect(row).not_to have_key(:_snapshot)
  end

  it 'uses half-open periods and saved thresholds independently from current settings' do
    _, older = read_report(vps, detected_at: now - 120, snapshot: { 'context' => { 'count_7d' => 2, 'count_30d' => 2 } })
    read_report(vps, detected_at: now - 60)
    SysConfig.find_by!(category: 'incident_policy_category', name: 'mode').update!(value: 'enforce')
    rows = projection.history(policy_key: 'category', from: now - 120, to: now - 60)[:rows]
    expect(rows.map { |row| row[:id] }).to eq([older.id])
    expect(rows.sole).to include(threshold_status: 'warning', effective_mode: 'observe', stop_enforced: false)
    expect { projection.history(from: now, to: now) }.to raise_error(ArgumentError)
  end

  it 'finds old outstanding work outside a period and old evaluations completed within daily activity' do
    _, evaluation = read_report(vps, detected_at: now - (60 * 86_400))
    action = read_action(evaluation, state: 'queued', mail_state: 'failed')
    outstanding = projection.history(scope: 'outstanding', from: now - 10, to: now - 1)
    expect(outstanding[:rows].map { |row| row[:id] }).to eq([evaluation.id])
    expect(outstanding[:meta]).to include(from: nil, to: nil)
    chain = read_stop_chain(vps, finished_at: now - 10)
    action.update!(transaction_chain: chain, mail_state: 'suppressed')
    rows = projection.history(activity: true, from: now - 86_400, to: now)[:rows]
    expect(rows.sole).to include(id: evaluation.id, activity_at: now - 10, activity_basis: 'stop_completed', physical_stop_action_id: action.id)
    expect(projection.history(scope: 'outstanding')[:rows]).to be_empty
  end

  it 'produces bounded daily payloads and nullable prepared links without extra per-row queries' do
    _, evaluation = read_report(vps, detected_at: now - 60)
    chain = read_stop_chain(vps, finished_at: now - 30)
    read_action(evaluation, state: 'queued', mail_state: 'failed', transaction_chain: chain)
    queries = []
    subscriber = ->(_name, _start, _finish, _id, event) { queries << event[:sql] if event[:sql].match?(/\A(?:SELECT|WITH)/) }
    payload = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      payload = projection.daily_summary(base_url: 'https://webui.example.test/')
    end
    expect(queries.length).to eq(4)
    expect(payload[:as_of]).to eq(now)
    expect(payload[:overview]).to include(total_count: 2, omitted_count: 0)
    expect(payload[:overview][:rows].first[:vps_url]).to include("veid=#{vps.id}")
    expect(payload[:overview][:rows].first[:last_incident_at]).to be_a(Time)
    transaction_url = "https://webui.example.test/?page=transactions&chain=#{chain.id}"
    expect(payload[:overview][:rows].find { |row| row[:policy_key] == 'category' }[:transaction_url]).to eq(transaction_url)
    expect(payload[:activity][:rows].find { |row| row[:id] == evaluation.id }[:transaction_url]).to eq(transaction_url)
    expect(payload[:outstanding][:rows].sole[:transaction_url]).to eq(transaction_url)
    expect(payload[:overview][:rows].find { |row| row[:policy_key] == 'content' }[:transaction_url]).to be_nil
    [nil, '', 'javascript:alert(1)'].each do |base_url|
      invalid = projection.daily_summary(base_url:)
      %i[overview activity outstanding].each do |collection|
        expect(invalid[collection][:url]).to be_nil
        expect(invalid[collection][:rows].map { |row| row[:transaction_url] }).to all(be_nil)
      end
    end
  end

  it 'normalizes and validates cutoffs and bounded input choices' do
    expect(described_class.new(now: now + 0.5).as_of).to eq(now)
    expect { described_class.new(now:, as_of: now + 1) }.to raise_error(ArgumentError)
    expect { described_class.new(now:, as_of: now - 86_401) }.to raise_error(ArgumentError)
    expect { projection.exposures(policy_key: 'retired') }.to raise_error(ArgumentError)
    expect { projection.exposures(sort: 'sql') }.to raise_error(ArgumentError)
    expect { projection.exposures(limit: 101) }.to raise_error(ArgumentError)
  end

  it 'uses actual retained mail timestamps and deduplicates a shared physical shutdown' do
    report, evaluation = read_report(vps, detected_at: now - 120)
    chain = read_stop_chain(vps, finished_at: now - 60)
    owner = read_action(evaluation, state: 'queued', transaction_chain: chain)
    follower_evaluation = report.incident_policy_evaluations.find_by!(policy_key: 'content')
    follower = read_action(follower_evaluation, state: 'queued', transaction_chain: chain, stop_owner_action: owner)
    send_transaction = Transaction.create!(transaction_chain: chain, handle: 9001, node: vps.node, queue: 'mail')
    send_transaction.update_columns(done: 1, status: 1, finished_at: now - 10)
    mail = MailLog.create!(to: 'synthetic@example.test', from: 'synthetic@example.test', cc: '', bcc: '', subject: 'Synthetic',
                           transaction_id: send_transaction.id, created_at: now - 20)
    owner.update!(mail_log: mail, mail_state: 'queued')
    rows = projection.history(scope: 'all')[:rows]
    expect(rows.map { |row| row[:physical_stop_action_id] }.uniq).to eq([owner.id])
    expect(rows.find { |row| row[:id] == evaluation.id }).to include(mail_state: 'sent', mail_queued_at: now - 20,
                                                                     mail_finished_at: now - 10, stop_completed_at: now - 60)
    expect(rows.find { |row| row[:id] == follower_evaluation.id }).to include(action_id: follower.id, stop_completed_at: now - 60)
    expect(owner.reload.mail_state).to eq('queued')
    send_transaction.update_columns(status: 0)
    expect(projection.history(scope: 'outstanding')[:rows].map { |row| row[:id] }).to include(evaluation.id)
    owner.update!(mail_state: 'suppressed')
    expect(projection.history(scope: 'all')[:rows].find { |row| row[:id] == evaluation.id }[:mail_state]).to eq('suppressed')
  end

  it 'keeps totals and page facts in one statement and caps the globally ordered daily collection' do
    13.times do
      item = build_standalone_vps_fixture.fetch(:vps)
      read_report(item, detected_at: now - 60)
    end
    query = nil
    subscriber = lambda do |_name, _start, _finish, _id, event|
      query = event[:sql] if event[:sql].start_with?('WITH')
    end
    result = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      result = projection.exposures(limit: 25)
    end
    expect(result[:meta]).to include(total_count: 26, next_offset: 25)
    expect(result[:rows].length).to eq(25)
    expect(query).to include('COUNT(*) AS total_count FROM filtered', 'LIMIT 25 OFFSET 0', 'LEFT JOIN page ON TRUE')
    expect(projection.daily_summary[:overview]).to include(total_count: 26, omitted_count: 1)
  end
end
