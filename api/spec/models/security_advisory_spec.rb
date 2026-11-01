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

  it 'exposes only published reports to guests and members while retaining all states for admins' do
    draft = build_advisory
    published = build_advisory
    published.update!(state: :published)
    retracted = build_advisory
    retracted.update!(state: :retracted)

    [nil, SpecSeed.user].each do |reader|
      expect(described_class.visible_to(reader).pluck(:id)).to contain_exactly(published.id)
    end
    expect(described_class.visible_to(SpecSeed.admin).pluck(:id))
      .to contain_exactly(draft.id, published.id, retracted.id)
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

    advisory.publish!(
      expected_content_revision: advisory.content_revision,
      published_by: SpecSeed.admin
    )

    expect(advisory.security_advisory_vpses.pluck(:vps_id)).to contain_exactly(user_vps.id, other_vps.id)
    expect(advisory.security_advisory_users.pluck(:user_id)).to contain_exactly(
      SpecSeed.user.id,
      SpecSeed.other_user.id
    )
  end

  it 'refuses to publish a draft revision other than the reviewed revision' do
    advisory = build_advisory
    add_mitigated_status!(advisory)
    add_not_affected_status!(advisory)

    expect do
      advisory.publish!(
        expected_content_revision: advisory.content_revision + 1,
        published_by: SpecSeed.admin
      )
    end.to raise_error(SecurityAdvisory::RevisionMismatch)

    expect(advisory.reload).to be_draft
  end

  describe 'original corrections' do
    def publish_advisory!
      advisory = build_advisory
      add_mitigated_status!(advisory)
      add_not_affected_status!(advisory)
      advisory.publish!(expected_content_revision: 0, published_by: SpecSeed.admin)
      advisory
    end

    it 'preserves omitted localized fields and never rebuilds or sends mail for text corrections' do
      advisory = publish_advisory!
      allow(advisory).to receive(:rebuild_affected!).and_call_original
      allow(advisory).to receive(:mail_chain).and_call_original

      advisory.update_content!({}, { SpecSeed.language => { summary: 'Corrected summary' } },
                               expected_content_revision: 0)

      translation = advisory.security_advisory_translations.find_by!(language: SpecSeed.language)
      expect(translation.summary).to eq('Corrected summary')
      expect(translation.description).to eq('Spec advisory description')
      expect(translation.response).to eq('Spec advisory response')
      expect(advisory.content_revision).to eq(1)
      expect(advisory).not_to have_received(:rebuild_affected!)
      expect(advisory).not_to have_received(:mail_chain)
    end

    it 'does not validate unrelated missing node assessments again on published corrections' do
      advisory = publish_advisory!
      advisory.security_advisory_node_statuses.find_by!(node: SpecSeed.other_node).destroy!
      status = advisory.security_advisory_node_statuses.find_by!(node: SpecSeed.node)

      advisory.update_content!({ name: 'Correction' }, expected_content_revision: 0)
      advisory.update_node_status!(status.id, {}, { SpecSeed.language => { note: 'Corrected note' } },
                                   expected_content_revision: 1)

      expect(advisory.content_revision).to eq(2)
      expect(status.reload.localized_note(SpecSeed.language)).to eq('Corrected note')
    end

    it 'rolls back original fields, translations and timestamp when translation persistence fails' do
      advisory = publish_advisory!
      before = advisory.attributes
      translations = advisory.security_advisory_translations.map(&:attributes)
      allow(advisory).to receive(:update_translations!).and_wrap_original do |method, *args|
        method.call(*args)
        raise 'translation persistence failed'
      end

      expect do
        advisory.update_content!({ name: 'Must roll back' },
                                 { SpecSeed.language => { summary: 'Must roll back' } },
                                 expected_content_revision: 0)
      end.to raise_error(RuntimeError, 'translation persistence failed')

      expect(advisory.reload.attributes).to eq(before)
      expect(advisory.security_advisory_translations.map(&:attributes)).to eq(translations)
    end

    it 'rolls back changed notes, projection inserts and deletions and derived users after a rebuild failure' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'before-correction')
      advisory = publish_advisory!
      status = advisory.security_advisory_node_statuses.find_by!(node: SpecSeed.node)
      status.update_translations!(SpecSeed.language => { note: 'Keep note' })
      before = advisory.attributes
      row = status.attributes
      projection = advisory.security_advisory_vpses.map(&:attributes)
      users = advisory.security_advisory_users.map(&:attributes)
      Vps.where(id: vps.id).update_all(node_id: SpecSeed.other_node.id)
      create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'after-correction')
      allow(advisory).to receive(:rebuild_affected_users!).and_wrap_original do |method|
        method.call
        raise 'projection persistence failed'
      end

      expect do
        advisory.update_node_status!(status.id, { vulnerable_until: Time.utc(2026, 1, 2) },
                                     { SpecSeed.language => { note: nil } }, expected_content_revision: 0)
      end.to raise_error(RuntimeError, 'projection persistence failed')

      expect(advisory.reload.attributes).to eq(before)
      expect(status.reload.attributes).to eq(row)
      expect(status.localized_note(SpecSeed.language)).to eq('Keep note')
      expect(advisory.security_advisory_vpses.reload.map(&:attributes)).to eq(projection)
      expect(advisory.security_advisory_users.reload.map(&:attributes)).to eq(users)
    end

    it 'keeps draft unresolved states and notes editable without rebuilding projections' do
      advisory = build_advisory
      status = add_not_affected_status!(advisory)
      allow(advisory).to receive(:rebuild_affected!).and_call_original
      %w[vulnerable unknown].each_with_index do |state, revision|
        advisory.update_node_status!(status.id, { state: },
                                     { SpecSeed.language => { note: state } },
                                     expected_content_revision: revision, expected_state: 'draft')
        expect(status.reload.state).to eq(state)
        expect(status.localized_note(SpecSeed.language)).to eq(state)
      end
      expect(advisory.content_revision).to eq(2)
      expect(advisory).not_to have_received(:rebuild_affected!)
    end

    def owned_relations(advisory)
      updates = advisory.security_advisory_updates.pluck(:id)
      nodes = advisory.security_advisory_node_statuses.pluck(:id)
      translations = SecurityAdvisoryTranslation.where(security_advisory_id: advisory.id)
      translations = translations.or(SecurityAdvisoryTranslation.where(security_advisory_update_id: updates))
      {
        report: SecurityAdvisory.where(id: advisory.id),
        cves: advisory.security_advisory_cves,
        translations:,
        updates: SecurityAdvisoryUpdate.where(id: updates),
        nodes: SecurityAdvisoryNodeStatus.where(id: nodes),
        notes: SecurityAdvisoryNodeStatusTranslation.where(security_advisory_node_status_id: nodes),
        vpses: advisory.security_advisory_vpses,
        users: advisory.security_advisory_users
      }
    end

    def add_update_and_note!(advisory)
      advisory.create_update!({}, { SpecSeed.language => { summary: 'Keep update history' } })
      advisory.security_advisory_node_statuses.first!.update_translations!(SpecSeed.language => { note: 'Node note' })
    end

    it 'deletes all owned report rows while preserving referenced objects, transaction concerns and mail history' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'deletion-reference')
      advisory = publish_advisory!
      add_update_and_note!(advisory)
      relations = owned_relations(advisory)
      expect(relations.values).to all(be_exists)
      chain = build_transaction_chain!
      concern = TransactionChainConcern.create!(transaction_chain: chain, class_name: 'SecurityAdvisory', row_id: advisory.id)
      log = MailLog.create!(user: SpecSeed.user, from: 'test@example.test', to: 'test@example.test',
                            cc: '', bcc: '', subject: 'Retained advisory mail')
      references = [vps, SpecSeed.user, SpecSeed.admin, SpecSeed.node, SpecSeed.environment, SpecSeed.location, concern, chain, log]

      advisory.destroy_content!(expected_content_revision: 0, expected_state: 'published')

      relations.each_value { |scope| expect(scope.exists?).to be(false) }
      references.each { |record| expect(record.class.exists?(record.id)).to be(true) }
    end

    it 'restores the complete owned cascade when a late dependent destroy fails' do
      create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'deletion-rollback')
      advisory = publish_advisory!
      add_update_and_note!(advisory)
      relations = owned_relations(advisory)
      before = relations.transform_values { |scope| scope.order(:id).map(&:attributes) }
      failure = lambda do |record|
        raise 'dependent destroy failed' if record.security_advisory_id == advisory.id
      end
      SecurityAdvisoryUpdate.set_callback(:destroy, :before, failure)
      begin
        expect do
          advisory.destroy_content!(expected_content_revision: 0)
        end.to raise_error(RuntimeError, 'dependent destroy failed')
      ensure
        SecurityAdvisoryUpdate.skip_callback(:destroy, :before, failure)
      end

      expect(relations.transform_values { |scope| scope.order(:id).map(&:attributes) }).to eq(before)
    end

    it 'rolls back a manual rebuild when its failure is caught inside an outer transaction' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'manual-rebuild-rollback')
      advisory = publish_advisory!
      relations = owned_relations(advisory)
      before = relations.transform_values { |scope| scope.order(:id).map(&:attributes) }
      Vps.where(id: vps.id).update_all(user_id: SpecSeed.other_user.id)
      allow(advisory).to receive(:rebuild_affected_users!).and_wrap_original do |method|
        method.call
        raise 'manual rebuild failed'
      end
      expect { advisory.rebuild_affected! }.to raise_error(RuntimeError, 'manual rebuild failed')
      expect(relations.transform_values { |scope| scope.order(:id).map(&:attributes) }).to eq(before)
    end

    it 'rolls back explicit update creation and state/time changes when announcement failure is caught' do
      advisory = publish_advisory!
      before = advisory.attributes
      allow(advisory).to receive(:mail_chain).and_raise('announcement failed')
      expect do
        advisory.create_update!({ state: 'retracted' }, { SpecSeed.language => { summary: 'Uncommitted update' } },
                                advisory_attrs: { published_at: nil }, send_mail: true)
      end.to raise_error(RuntimeError, 'announcement failed')
      expect(advisory.reload.attributes).to eq(before)
      expect(advisory.security_advisory_updates).to be_empty
      expect(SecurityAdvisoryTranslation.where(summary: 'Uncommitted update')).to be_empty
    end

    it 'rolls back earlier child translations when a later translation fails inside an outer transaction' do
      advisory = publish_advisory!
      update = advisory.create_update!({}, { SpecSeed.language => { summary: 'Original update' } })
      before = update.security_advisory_translations.map(&:attributes)
      failure = lambda do |record|
        raise 'child translation failed' if record.security_advisory_update_id == update.id && record.summary == 'Fail second'
      end
      SecurityAdvisoryTranslation.set_callback(:save, :before, failure)
      begin
        expect do
          update.update_translations!(
            SpecSeed.language => { summary: 'First write' },
            Language.find_by!(code: 'cs') => { summary: 'Fail second' }
          )
        end.to raise_error(RuntimeError, 'child translation failed')
      ensure
        SecurityAdvisoryTranslation.skip_callback(:save, :before, failure)
      end
      expect(update.security_advisory_translations.reload.map(&:attributes)).to eq(before)
    end

    %i[create delete].each do |operation|
      it "rolls back published node #{operation}, notes and all projections on rebuild failure" do
        create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: "node-#{operation}-rollback")
        advisory = publish_advisory!
        add_update_and_note!(advisory)
        relations = owned_relations(advisory)
        before = relations.transform_values { |scope| scope.order(:id).map(&:attributes) }
        node = create_node!
        create_vps!(user: SpecSeed.other_user, node: node, hostname: 'new-node-vps')
        allow(advisory).to receive(:rebuild_affected_users!).and_wrap_original do |method|
          method.call
          raise 'projection persistence failed'
        end
        expect do
          if operation == :create
            advisory.create_node_status!({ node:, state: 'mitigated', vulnerable_until: Time.utc(2026, 2, 1),
                                           mitigated_since: Time.utc(2026, 2, 1, 0, 5) },
                                         { SpecSeed.language => { note: 'Must roll back' } }, expected_content_revision: 0)
          else
            advisory.delete_node_status!(advisory.security_advisory_node_statuses.find_by!(node: SpecSeed.node).id,
                                         expected_content_revision: 0)
          end
        end.to raise_error(RuntimeError, 'projection persistence failed')
        expect(relations.transform_values { |scope| scope.order(:id).map(&:attributes) }).to eq(before)
        expect(advisory.security_advisory_node_statuses.where(node:)).to be_empty
        expect(SecurityAdvisoryNodeStatusTranslation.where(note: 'Must roll back')).to be_empty
      end
    end
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

    node_status_translation = SecurityAdvisoryNodeStatusTranslation.new(
      security_advisory_node_status_id: missing,
      language: SpecSeed.language,
      note: 'Orphan node note'
    )

    expect(node_status_translation).not_to be_valid
    expect(node_status_translation.errors[:security_advisory_node_status]).not_to be_empty
  end

  it 'removes localized node notes when the advisory is destroyed' do
    advisory = build_advisory
    status = add_not_affected_status!(advisory)
    translation = status.security_advisory_node_status_translations.create!(
      language: SpecSeed.language,
      note: 'Spec node note'
    )

    advisory.destroy!

    expect(SecurityAdvisoryNodeStatusTranslation.where(id: translation.id)).to be_empty
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

    advisory.publish!(
      expected_content_revision: advisory.content_revision,
      send_mail: false,
      published_by: SpecSeed.admin
    )

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
