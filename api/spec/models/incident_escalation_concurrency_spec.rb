require 'spec_helper'
require 'timeout'

RSpec.describe IncidentEscalation, :no_transaction do
  before { install_incident_policy_fixture }

  def with_policy_context(&block)
    with_current_context(user: SpecSeed.admin) do |session|
      block.call
    ensure
      session.destroy!
    end
  end

  %i[node_event ordinary].each do |producer|
    it "serializes concurrent #{producer} creation before decisions and does not re-enroll persisted reports" do
      if producer == :ordinary
        declaration = IncidentEscalation::Configuration.new
        declaration.rule(:oomd) do
          labels en: 'Ordinary category'
          limits warning: 5, stop: 10
          applies_if { |ctx| ctx.report[:codename] == 'ordinary_category' }
        end
        stub_const('IncidentEscalation::RULES', declaration.rules.freeze)
      end
      vps = nil
      mode = SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode')
      original_mode = mode.value
      with_policy_context do
        # Ingestion needs only a persisted VPS; provisioning here would commit
        # changes to shared seed quotas, node status and dataset accounting.
        vps = Vps.create!(user: SpecSeed.user, node: SpecSeed.node, os_template: SpecSeed.os_template,
                          dns_resolver: SpecSeed.dns_resolver, hostname: 'concurrent-incidents',
                          object_state: :active, confirmed: :confirmed)
        mode.update!(value: 'observe')
        9.times do |i|
          IncidentReport.create!(user: vps.user, vps:, codename: producer == :ordinary ? 'ordinary_category' : 'oomd', subject: 'OOM', text: 'OOM', detected_at: Time.now - 100 - i,
                                 source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
        end
        mode.update!(value: 'enforce')
      end
      allow(described_class).to receive(:process!) # Exercise ingestion/decision commits without node work.
      ready = Queue.new
      resume = Queue.new
      now = Time.now.utc.change(usec: 0)
      workers = 2.times.map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            with_policy_context do
              local_vps = Vps.find(vps.id)
              ready << true
              resume.pop
              if producer == :ordinary
                IncidentReport.create!(user: local_vps.user, vps: local_vps, codename: 'ordinary_category',
                                       subject: 'Manual report', text: 'Imported evidence', detected_at: now - i)
              else
                VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(local_vps, node: local_vps.node, action: 'restart', time: now - i, now:)
              end
            end
          end
        end
      end
      2.times { Timeout.timeout(10) { ready.pop } }
      2.times { resume << true }
      Timeout.timeout(30) { workers.each(&:value) }
      with_policy_context do
        if producer == :ordinary
          IncidentReport.where(vps:).last.update!(text: 'Corrected evidence')
        else
          VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps.reload, node: vps.node, action: 'restart', time: now, now:)
        end
      end
      expect(IncidentReport.ordinary.where(vps: vps).count).to eq(11)
      expect(IncidentPolicyEvaluation.where(incident_report_id: IncidentReport.where(vps:).select(:id)).count).to eq(11)
      expect(VpsIncidentAction.where(vps: vps, kind: 'stop').count).to eq(1)
    ensure
      workers&.each { |worker| worker.join(5) || worker.kill.join }
      if vps
        VpsIncidentAction.where(vps: vps).delete_all
        VpsIncidentPolicy.where(vps: vps).delete_all
        IncidentPolicyEvaluation.where(incident_report_id: IncidentReport.where(vps:).select(:id)).delete_all
        IncidentReport.where(vps: vps).delete_all
        ObjectHistory.where(tracked_object: vps).delete_all
        PaperTrail::Version.where(item_type: 'Vps', item_id: vps.id).delete_all
        Vps.where(id: vps.id).delete_all
      end
      mode&.update_column(:value, original_mode)
    end
  end

  it 'uses current memberships, settings and warning exclusions after an older outer transaction snapshot' do
    calls = []
    declaration = IncidentEscalation::Configuration.new
    %w[stop_policy warn_policy].each do |key|
      declaration.rule(key) do
        labels en: key
        limits warning: 1, stop: 10
        applies_if do |ctx|
          calls << [ctx.report[:id], ctx.policy_key, ctx.count_30d]
          true
        end
      end
    end
    stub_const('IncidentEscalation::RULES', declaration.rules.freeze)
    vps = nil
    worker = nil
    with_policy_context do
      vps = Vps.create!(user: SpecSeed.user, node: SpecSeed.node, os_template: SpecSeed.os_template,
                        dns_resolver: SpecSeed.dns_resolver, hostname: 'outer-snapshot-incidents',
                        object_state: :active, confirmed: :confirmed)
      declaration.rules.each_value do |rule|
        SysConfig.create!(category: rule.category, name: 'mode', value: 'observe', data_type: 'String')
      end
      vps.vps_incident_policies.create!(policy_key: 'stop_policy', stop_limit_override: 10)
      IncidentReport.transaction do
        # Deliberately establish a consistent read before the other connection
        # commits. Mutation reads must not reuse it after acquiring the locks.
        expect(IncidentReport.where(vps:).count).to eq(0)
        expect(VpsIncidentAction.where(vps:).count).to eq(0)
        expect(SysConfig.find_by!(category: 'incident_policy_stop_policy', name: 'mode').value).to eq('observe')
        expect(vps.vps_incident_policies.find_by!(policy_key: 'stop_policy').stop_limit_override).to eq(10)
        worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            with_policy_context do
              local_vps = Vps.find(vps.id)
              SysConfig.where(category: declaration.rules.values.map(&:category), name: 'mode').each { |row| row.update!(value: 'enforce') }
              described_class.update_policy!(local_vps, 'stop_policy', stop_limit_override: 2)
              IncidentReport.create!(vps: local_vps, user: local_vps.user, subject: 'Committed first', text: 'Evidence', detected_at: Time.now).id
            end
          end
        end
        first_id = Timeout.timeout(30) { worker.value }
        report = IncidentReport.create!(vps:, user: vps.user, subject: 'Created after snapshot', text: 'Evidence', detected_at: Time.now)
        outcomes = report.incident_policy_evaluations.index_by(&:policy_key)
        expect(calls.select { |id, _key, _count| id == report.id }.map(&:last)).to eq([1, 1])
        expect(outcomes.values.map { |row| row.snapshot.fetch('context').fetch('count_30d') }).to eq([2, 2])
        expect(outcomes.fetch('stop_policy').snapshot).to include('decision' => 'stop', 'effective' => include('stop_limit' => 2, 'mode' => 'enforce'))
        expect(outcomes.fetch('warn_policy').snapshot.fetch('decision')).to eq('none')
        actions = VpsIncidentAction.where(vps:).order(:id).lock.to_a
        expect(actions.count { |action| action.kind == 'stop' }).to eq(1)
        expect(actions.count { |action| action.kind == 'warning' && action.policy_key == 'warn_policy' }).to eq(1)
        stop = actions.find { |action| action.kind == 'stop' }
        expect(stop.contributor_snapshot.fetch('total')).to eq(2)
        expect(stop.contributor_snapshot.fetch('entries').map { |entry| entry.fetch('id') }).to contain_exactly(first_id, report.id)
      end
    end
  ensure
    worker&.join(5) || worker&.kill&.join
    if vps
      VpsIncidentAction.where(vps:).delete_all
      VpsIncidentPolicy.where(vps:).delete_all
      IncidentPolicyEvaluation.where(incident_report_id: IncidentReport.where(vps:).select(:id)).delete_all
      IncidentReport.where(vps:).delete_all
      PaperTrail::Version.where(item_type: 'Vps', item_id: vps.id).delete_all
      Vps.where(id: vps.id).delete_all
    end
    SysConfig.where(category: %w[incident_policy_stop_policy incident_policy_warn_policy]).delete_all
  end
end
