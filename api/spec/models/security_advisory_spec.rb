# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecurityAdvisory do
  include CoreResourceSpecHelpers

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.location
    SpecSeed.node
    SpecSeed.pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
    ensure_alert_notification_templates!
    ensure_mailer_available!
  end

  def build_advisory(cves: 'CVE-2026-2000')
    advisory = described_class.create!(
      state: :draft,
      name: 'Spec advisory',
      created_by: SpecSeed.admin
    )
    advisory.update_cves!(cves)
    advisory.security_advisory_translations.create!(
      language: SpecSeed.language,
      summary: 'Spec advisory summary',
      description: 'Spec advisory description',
      response: 'Spec advisory response'
    )
    advisory.reload
  end

  def add_mitigated_status!(advisory)
    SecurityAdvisoryNodeStatus.create!(
      security_advisory: advisory,
      node: SpecSeed.node,
      state: :mitigated,
      vulnerable_until: Time.utc(2026, 1, 1, 10, 0, 0),
      mitigated_since: Time.utc(2026, 1, 1, 10, 5, 0)
    )
  end

  def add_not_affected_status!(advisory)
    SecurityAdvisoryNodeStatus.create!(
      security_advisory: advisory,
      node: SpecSeed.other_node,
      state: :not_affected
    )
  end

  it 'normalizes and replaces CVE identifiers' do
    advisory = build_advisory(cves: 'cve-2026-2001, CVE-2026-2002 CVE-2026-2001')

    expect(advisory.cve_ids).to eq(%w[CVE-2026-2001 CVE-2026-2002])

    advisory.update_cves!('CVE-2026-2003')

    expect(advisory.cve_ids).to eq(%w[CVE-2026-2003])
  end

  it 'snapshots currently affected VPSes when published' do
    advisory = build_advisory
    add_mitigated_status!(advisory)
    add_not_affected_status!(advisory)
    user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-advisory-user')
    other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-advisory-other')

    advisory.publish!(published_by: SpecSeed.admin)

    expect(advisory.security_advisory_vpses.pluck(:vps_id)).to contain_exactly(user_vps.id, other_vps.id)
    expect(advisory.security_advisory_users.pluck(:user_id)).to contain_exactly(
      SpecSeed.user.id,
      SpecSeed.other_user.id
    )
  end

  it 'rejects raw child rows for missing advisory ids' do
    missing = described_class.maximum(:id).to_i + 100
    vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-advisory-orphan')

    rows = {
      cve: SecurityAdvisoryCve.new(
        security_advisory_id: missing,
        cve_id: 'CVE-2026-2999'
      ),
      node_status: SecurityAdvisoryNodeStatus.new(
        security_advisory_id: missing,
        node: SpecSeed.node,
        state: :not_affected
      ),
      update: SecurityAdvisoryUpdate.new(
        security_advisory_id: missing
      ),
      user: SecurityAdvisoryUser.new(
        security_advisory_id: missing,
        user: SpecSeed.user
      ),
      vps: SecurityAdvisoryVps.new(
        security_advisory_id: missing,
        vps: vps,
        user: vps.user,
        environment: vps.node.location.environment,
        location: vps.node.location,
        node: vps.node,
        node_state: :not_affected
      ),
      translation: SecurityAdvisoryTranslation.new(
        security_advisory_id: missing,
        language: SpecSeed.language,
        summary: 'Orphan translation'
      )
    }

    rows.each_value do |row|
      expect(row).not_to be_valid
      expect(row.errors[:security_advisory]).not_to be_empty
    end

    update_translation = SecurityAdvisoryTranslation.new(
      security_advisory_update_id: missing,
      language: SpecSeed.language,
      summary: 'Orphan update translation'
    )

    expect(update_translation).not_to be_valid
    expect(update_translation.errors[:security_advisory_update]).not_to be_empty
  end

  it 'routes affected user notifications only when requested' do
    advisory = build_advisory
    add_mitigated_status!(advisory)
    add_not_affected_status!(advisory)
    user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-advisory-mail')
    other_vps = create_vps!(
      user: SpecSeed.other_user,
      node: SpecSeed.node,
      hostname: 'spec-advisory-muted'
    )
    SpecSeed.user.update!(mailer_enabled: true, object_state: :active)
    SpecSeed.other_user.update!(mailer_enabled: false, object_state: :active)

    advisory.publish!(send_mail: false, published_by: SpecSeed.admin)

    expect(Event.where(event_type: 'security_advisory.announced')).to be_empty

    update = advisory.create_update!(
      {},
      { SpecSeed.language => { summary: 'Follow-up' } },
      send_mail: true
    )
    events = Event
             .where(
               event_type: 'security_advisory.updated',
               source_class: update.class.name,
               source_id: update.id
             )
             .includes(:event_deliveries)
             .to_a
    user_event = events.detect { |event| event.user_id == SpecSeed.user.id }
    muted_event = events.detect { |event| event.user_id == SpecSeed.other_user.id }

    expect(events.size).to eq(2)
    expect(user_event).to be_routed_routing_state
    expect(user_event.parameters).to include(
      'advisory_id' => advisory.id,
      'advisory_name' => advisory.name,
      'update_id' => update.id,
      'affected_vps_count' => 1
    )
    expect(user_event.parameters.fetch('affected_vpses')).to contain_exactly(
      a_hash_including(
        'vps_id' => user_vps.id,
        'vps_hostname' => user_vps.hostname
      )
    )
    expect(user_event.event_deliveries.sole).to be_released_state
    expect(user_event.event_deliveries.sole.mail_log).to be_present

    expect(muted_event).to be_suppressed_routing_state
    expect(muted_event.parameters.fetch('affected_vpses')).to contain_exactly(
      a_hash_including(
        'vps_id' => other_vps.id,
        'vps_hostname' => other_vps.hostname
      )
    )
    expect(muted_event.event_deliveries.sole).to be_skipped_state
    expect(muted_event.event_deliveries.sole.error_summary).to include('does not notify')
    expect(advisory.last_chain).to be_nil
  end

  it 'rebuilds advisory e-mail variables from persisted event parameters' do
    advisory = build_advisory
    add_mitigated_status!(advisory)
    add_not_affected_status!(advisory)
    user_vps = create_vps!(
      user: SpecSeed.user,
      node: SpecSeed.node,
      hostname: 'spec-advisory-fallback'
    )
    create_vps!(
      user: SpecSeed.other_user,
      node: SpecSeed.node,
      hostname: 'spec-advisory-foreign'
    )
    advisory.publish!(send_mail: false, published_by: SpecSeed.admin)
    update = advisory.create_update!(
      {},
      { SpecSeed.language => { summary: 'Fallback follow-up' } },
      send_mail: false
    )
    event = VpsAdmin::API::Events.emit!(
      'security_advisory.updated',
      user: SpecSeed.user,
      parameters: {
        advisory_id: advisory.id,
        update_id: update.id
      },
      route: false
    )

    vars = VpsAdmin::API::Events.template_options_for(event).fetch(:vars)

    expect(vars).to include(
      advisory:,
      a: advisory,
      update:,
      user: SpecSeed.user
    )
    expect(vars.fetch(:vpses).map(&:vps_id)).to eq([user_vps.id])
  end
end
