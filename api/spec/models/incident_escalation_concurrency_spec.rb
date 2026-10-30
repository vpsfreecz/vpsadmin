require 'spec_helper'
require 'timeout'

RSpec.describe IncidentEscalation, :no_transaction do
  def with_policy_context(&block)
    with_current_context(user: SpecSeed.admin) do |session|
      block.call
    ensure
      session.destroy!
    end
  end

  it 'serializes concurrent threshold events and deduplicates redelivery before decisions or mail' do
    vps = nil
    mode = SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode')
    original_mode = mode.value
    with_policy_context do
      # Ingestion needs only a persisted VPS; provisioning here would commit
      # changes to shared seed quotas, node status and dataset accounting.
      vps = Vps.create!(user: SpecSeed.user, node: SpecSeed.node, os_template: SpecSeed.os_template,
                        dns_resolver: SpecSeed.dns_resolver, hostname: 'concurrent-incidents',
                        object_state: :active, confirmed: :confirmed)
      mode.update!(value: 'enforce')
      9.times do |i|
        IncidentReport.create!(user: vps.user, vps:, codename: 'oomd', subject: 'OOM', text: 'OOM', detected_at: Time.now - 100 - i,
                               source_key: SecureRandom.hex(32), source_kind: 'node_vps_event', source_action: 'restart', source_node_id: vps.node_id)
      end
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
            VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(local_vps, node: local_vps.node, action: 'restart', time: now - i, now:)
          end
        end
      end
    end
    2.times { Timeout.timeout(10) { ready.pop } }
    2.times { resume << true }
    Timeout.timeout(30) { workers.each(&:value) }
    with_policy_context do
      VpsAdmin::Supervisor::Node::VpsEvents.record_oomd_event(vps.reload, node: vps.node, action: 'restart', time: now, now:)
    end
    expect(IncidentReport.where(vps: vps).count).to eq(11)
    expect(VpsIncidentAction.where(vps: vps, kind: 'stop').count).to eq(1)
  ensure
    workers&.each { |worker| worker.join(5) || worker.kill.join }
    if vps
      VpsIncidentAction.where(vps: vps).delete_all
      VpsIncidentPolicy.where(vps: vps).delete_all
      IncidentReport.where(vps: vps).delete_all
      ObjectHistory.where(tracked_object: vps).delete_all
      PaperTrail::Version.where(item_type: 'Vps', item_id: vps.id).delete_all
      Vps.where(id: vps.id).delete_all
    end
    mode&.update_column(:value, original_mode)
  end
end
