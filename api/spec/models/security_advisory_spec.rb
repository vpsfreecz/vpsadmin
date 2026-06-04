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

  it 'mails affected users only when requested' do
    advisory = build_advisory
    add_mitigated_status!(advisory)
    add_not_affected_status!(advisory)
    create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-advisory-mail')
    SpecSeed.user.update!(mailer_enabled: true, object_state: :active)
    attempts = []

    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      attempts << [name, opts]
      build_mail_log_double
    end

    advisory.publish!(send_mail: false, published_by: SpecSeed.admin)

    expect(MailTemplate).not_to have_received(:send_mail!)

    advisory.create_update!(
      {},
      { SpecSeed.language => { summary: 'Follow-up' } },
      send_mail: true
    )

    expect(attempts.size).to eq(1)
    name, opts = attempts.first
    expect(name).to eq(:security_advisory_user_update)
    expect(opts[:user]).to eq(SpecSeed.user)
    expect(opts.fetch(:vars)).to include(
      advisory: advisory,
      a: advisory,
      user: SpecSeed.user
    )
  end
end
