require 'spec_helper'

RSpec.describe IncidentReport do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:now) { Time.now.utc.change(usec: 0) }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { travel_to(now) { example.run } }
  end

  def configure_rules(mode: 'observe', &block)
    declarations = IncidentEscalation::Configuration.new
    declarations.instance_eval(&block)
    stub_const('IncidentEscalation::RULES', declarations.rules.sort.to_h.freeze)
    declarations.rules.each_value do |rule|
      SysConfig.create!(category: rule.category, name: 'mode', value: mode, data_type: 'String')
    end
  end

  def ordinary(**values)
    described_class.new(user: vps.user, vps:, codename: 'abuse', subject: 'Imported report',
                        text: 'Private source details', detected_at: now, **values)
  end

  it 'has no policies without declarations and never invents a builtin OOM policy' do
    expect(IncidentEscalation::RULES).to be_empty
    report = ordinary(codename: 'oomd').tap(&:save!)
    expect(report.incident_policy_evaluations).to be_empty
    expect(VpsIncidentSummary.policy_rows([vps]).fetch(vps.id)).to eq([])
  end

  it 'evaluates two config-only non-OOM policies on save with a frozen plain context and no dry-run effects' do
    contexts = []
    configure_rules do
      rule :z_text do
        labels en: 'Text policy'
        limits warning: 3, stop: 9
        applies_if do |ctx|
          contexts << ctx
          ctx.report[:text].include?('Private')
        end
      end
      rule :a_category do
        labels en: 'Category policy'
        limits warning: 2, stop: 4
        applies_if do |ctx|
          contexts << ctx
          ctx.report[:codename] == 'abuse'
        end
      end
    end
    report = ordinary(filed_by: SpecSeed.admin)
    expect(contexts).to be_empty
    expect(report.incident_policy_evaluations).to be_empty
    report.save!
    expect(contexts.map(&:policy_key)).to eq(%w[a_category z_text])
    expect(contexts.map(&:count_30d)).to eq([0, 0])
    ctx = contexts.first
    expect(ctx.report).to include(id: report.id, codename: 'abuse', text: 'Private source details',
                                  user_id: vps.user_id, vps_id: vps.id, filed_by_id: SpecSeed.admin.id)
    expect(ctx.source).to eq(kind: nil, key: nil, node_id: nil, action: nil)
    expect { ctx.report[:text].replace('changed') }.to raise_error(FrozenError)
    expect { ctx.source[:key] = 'forged' }.to raise_error(FrozenError)
    expect(report.incident_policy_evaluations.map(&:matched)).to eq([true, true])
    expect(report.incident_policy_evaluations.map { |e| e.snapshot['context']['count_30d'] }).to eq([1, 1])
    expect(report.incident_policy_evaluations.to_json).not_to include('Private source details')
    report.update!(text: 'Changed source')
    VpsIncidentSummary.load([vps])
    IncidentEscalation.process!(vps)
    expect(contexts.size).to eq(2)
    expect(report.incident_policy_evaluations.map(&:matched)).to eq([true, true])
  end

  it 'rolls report, all memberships and prepared actions back together and evaluates a retried save once' do
    calls = 0
    configure_rules(mode: 'notify') do
      rule :generic do
        labels en: 'Generic'
        limits warning: 1, stop: 2
        applies_if do |_ctx|
          calls += 1
          true
        end
      end
    end
    report = ordinary
    initial = [described_class.count, IncidentPolicyEvaluation.count, VpsIncidentAction.count]
    expect do
      described_class.transaction(requires_new: true) do
        report.save!
        expect(report.incident_policy_evaluations.sole.matched).to be(true)
        expect(vps.vps_incident_actions.sole.kind).to eq('warning')
        raise 'roll back ordinary creation'
      end
    end.to raise_error('roll back ordinary creation')
    expect([described_class.count, IncidentPolicyEvaluation.count, VpsIncidentAction.count]).to eq(initial)
    report.save!
    expect(calls).to eq(2)
    expect(report.incident_policy_evaluations.count).to eq(1)
    expect(vps.vps_incident_actions.count).to eq(1)
    report.reload.save!
    expect(calls).to eq(2)
  end

  it 'retains explicit Stop or Suspend membership without preparing a duplicate automatic effect' do
    configure_rules(mode: 'enforce') do
      rule :any_report do
        labels en: 'Any report'
        limits warning: 1, stop: 1
      end
    end
    %w[stop suspend].each do |action|
      report = ordinary(vps_action: action).tap(&:save!)
      expect(report.incident_policy_evaluations.sole).to have_attributes(matched: true, state: 'recorded')
      expect(report.incident_policy_evaluations.sole.snapshot['decision']).to eq('none')
    end
    expect(vps.vps_incident_actions).to be_empty
    expect(IncidentEscalation.new(vps, policy_key: 'any_report').counts).to eq([2, 2])
  end

  it 'does not invoke selectors for predecessor ownership or policy notices' do
    calls = 0
    configure_rules do
      rule :generic do
        labels en: 'Generic'
        limits warning: 1, stop: 2
        applies_if do |_ctx|
          calls += 1
          true
        end
      end
    end
    vps.update_columns(incident_accounting_since: now)
    old = ordinary(detected_at: now - 1).tap(&:save!)
    foreign = ordinary(user: SpecSeed.other_user).tap(&:save!)
    notice = ordinary(source_kind: 'incident_policy_notice').tap(&:save!)
    expect([old, foreign].map { |r| r.incident_policy_evaluations.sole.matched }).to eq([false, false])
    expect(notice.incident_policy_evaluations).to be_empty
    expect(calls).to eq(0)
  end
end
