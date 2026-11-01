# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe SecurityAdvisory, :no_transaction do
  let(:fixture) { {} }

  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context(user: SpecSeed.admin) do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  def finish_threads(*threads)
    error = nil
    threads.compact.each do |thread|
      thread.join(25) || thread.kill.join
    rescue StandardError, RSpec::Expectations::ExpectationNotMetError => e
      error ||= e
    end
    raise error if error
  end

  before do
    unlock_transaction_signer!
    connection_thread do
      vps = create_vps_for_dataset!(user: SpecSeed.user, node: SpecSeed.node, dataset_in_pool: nil)
      fixture.merge!(vps: vps, map: vps.user_namespace_map, namespace: vps.user_namespace_map.user_namespace)
      advisory = described_class.create!(state: :draft, name: 'Concurrent advisory', created_by: SpecSeed.admin)
      fixture[:advisory] = advisory
      advisory.update_cves!('CVE-2026-2100')
      fixture[:status] = advisory.security_advisory_node_statuses.create!(
        node: SpecSeed.node, state: :mitigated,
        vulnerable_until: Time.utc(2026, 1, 1), mitigated_since: Time.utc(2026, 1, 1, 0, 5)
      )
      advisory.security_advisory_node_statuses.create!(node: SpecSeed.other_node, state: :not_affected)
      advisory.publish!(expected_content_revision: 0, published_by: SpecSeed.admin)
    end.value
  end

  after do
    connection_thread do
      fixture[:advisory]&.destroy!
      Vps.where(id: fixture[:vps]&.id).delete_all
      UserNamespaceMap.where(id: fixture[:map]&.id).delete_all
      UserNamespace.where(id: fixture[:namespace]&.id).delete_all
      fixture.each_value do |record|
        PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).delete_all
      end
    end.value
  end

  it 'allows exactly one of two corrections using the same revision to commit' do
    ready = Queue.new
    resume = Queue.new
    workers = %w[first second].map do |name|
      connection_thread do
        advisory = described_class.find(fixture[:advisory].id)
        ready << true
        resume.pop
        advisory.update_content!({ name: }, expected_content_revision: 0)
        :updated
      rescue SecurityAdvisory::RevisionMismatch
        :conflict
      end
    end
    2.times { Timeout.timeout(10) { ready.pop } }
    2.times { resume << true }
    results = Timeout.timeout(20) { workers.map(&:value) }

    expect(results).to contain_exactly(:updated, :conflict)
    expect(fixture[:advisory].reload.content_revision).to eq(1)
    expect(fixture[:advisory].name).to be_in(%w[first second])
  ensure
    2.times { resume << true } if resume
    finish_threads(*workers) if workers
  end

  it 'serializes a manual rebuild behind a correction even with older loaded projections' do
    ready = Queue.new
    resume = Queue.new
    correcting = Queue.new
    commit = Queue.new
    rebuilding = Queue.new
    worker = connection_thread do
      described_class.transaction do
        advisory = described_class.find(fixture[:advisory].id)
        advisory.security_advisory_node_statuses.load
        advisory.security_advisory_vpses.load
        advisory.security_advisory_users.load
        ready << true
        resume.pop
        rebuilding << true
        advisory.rebuild_affected!
      end
    end
    Timeout.timeout(10) { ready.pop }
    correction = connection_thread do
      advisory = described_class.find(fixture[:advisory].id)
      advisory.with_lock do
        advisory.update_node_status!(fixture[:status].id, { state: 'not_affected' }, expected_content_revision: 0)
        correcting << true
        commit.pop
      end
    end
    Timeout.timeout(10) { correcting.pop }
    resume << true
    Timeout.timeout(10) { rebuilding.pop }
    expect(worker.join(0.1)).to be_nil
    commit << true
    Timeout.timeout(20) { [correction, worker].each(&:value) }

    expect(fixture[:advisory].security_advisory_vpses.reload).to be_empty
    expect(fixture[:advisory].security_advisory_users.reload).to be_empty
    expect(fixture[:advisory].reload.content_revision).to eq(1)
  ensure
    resume << true if resume
    commit << true if commit
    finish_threads(correction, worker)
  end

  it 'uses current child fields, inserted notes, owners and projections after an older transaction read' do
    ready = Queue.new
    resume = Queue.new
    until_time = Time.utc(2026, 2, 1)
    since_time = Time.utc(2026, 2, 1, 0, 10)
    worker = connection_thread do
      described_class.transaction do
        advisory = described_class.find(fixture[:advisory].id)
        advisory.security_advisory_node_statuses.load
        fixture[:status].reload.security_advisory_node_status_translations.load
        advisory.security_advisory_vpses.load
        advisory.security_advisory_users.load
        ready << true
        resume.pop
        advisory.update_node_status!(fixture[:status].id, { mitigated_since: since_time },
                                     { SpecSeed.language => { note: 'Second correction' } },
                                     expected_content_revision: 1)
      end
    end
    Timeout.timeout(10) { ready.pop }
    connection_thread do
      Vps.where(id: fixture[:vps].id).update_all(user_id: SpecSeed.other_user.id)
      described_class.find(fixture[:advisory].id).update_node_status!(
        fixture[:status].id, { vulnerable_until: until_time },
        { SpecSeed.language => { note: 'First correction' } }, expected_content_revision: 0
      )
    end.value
    resume << true
    Timeout.timeout(20) { worker.value }

    status = fixture[:status].reload
    expect(status.vulnerable_until).to eq(until_time)
    expect(status.mitigated_since).to eq(since_time)
    expect(status.security_advisory_node_status_translations.count).to eq(1)
    expect(status.localized_note(SpecSeed.language)).to eq('Second correction')
    projection = fixture[:advisory].security_advisory_vpses.reload.sole
    expect(projection.user_id).to eq(SpecSeed.other_user.id)
    expect(projection.vulnerable_until).to eq(until_time)
    expect(projection.mitigated_since).to eq(since_time)
    user = fixture[:advisory].security_advisory_users.reload.sole
    expect([user.user_id, user.vps_count]).to eq([SpecSeed.other_user.id, 1])
    expect(fixture[:advisory].reload.content_revision).to eq(2)
  ensure
    resume << true if resume
    finish_threads(worker)
  end

  it 'rejects a guarded draft edit after publication without changing the publication revision' do
    fixture[:advisory].update!(state: :draft, published_at: nil, published_by: nil)
    ready = Queue.new
    resume = Queue.new
    worker = connection_thread do
      described_class.transaction do
        advisory = described_class.find(fixture[:advisory].id)
        expect(advisory).to be_draft
        ready << true
        resume.pop
        advisory.update_content!({ name: 'Crossed publication' },
                                 expected_content_revision: 0, expected_state: 'draft')
      end
    rescue SecurityAdvisory::StateMismatch
      :conflict
    end
    Timeout.timeout(10) { ready.pop }
    connection_thread do
      described_class.find(fixture[:advisory].id).publish!(expected_content_revision: 0, published_by: SpecSeed.admin)
    end.value
    resume << true
    expect(Timeout.timeout(20) { worker.value }).to eq(:conflict)
    expect(fixture[:advisory].reload).to be_published
    expect(fixture[:advisory].content_revision).to eq(0)
    expect(fixture[:advisory].name).to eq('Concurrent advisory')
  ensure
    resume << true if resume
    finish_threads(worker)
  end

  it 'checks the current revision when deletion waits for a successful correction' do
    corrected = Queue.new
    deleting = Queue.new
    commit = Queue.new
    editor = connection_thread do
      advisory = described_class.find(fixture[:advisory].id)
      advisory.with_lock do
        advisory.update_content!({ name: 'Committed correction' }, expected_content_revision: 0)
        corrected << true
        commit.pop
      end
    end
    Timeout.timeout(10) { corrected.pop }
    deleter = connection_thread do
      advisory = described_class.find(fixture[:advisory].id)
      deleting << true
      advisory.destroy_content!(expected_content_revision: 0)
    rescue SecurityAdvisory::RevisionMismatch
      :conflict
    end
    Timeout.timeout(10) { deleting.pop }
    commit << true
    Timeout.timeout(20) { editor.value }
    expect(Timeout.timeout(20) { deleter.value }).to eq(:conflict)
    expect(fixture[:advisory].reload.name).to eq('Committed correction')
    expect(fixture[:advisory].content_revision).to eq(1)
  ensure
    commit << true if commit
    finish_threads(editor, deleter)
  end

  %i[correction update_creation update_translation].each do |operation|
    it "refuses stale #{operation} after concurrent parent deletion without leaving child rows" do
      update = connection_thread do
        described_class.find(fixture[:advisory].id).create_update!(
          {}, { SpecSeed.language => { summary: 'Original update' } }
        )
      end.value
      ready = Queue.new
      resume = Queue.new
      worker = connection_thread do
        described_class.transaction do
          advisory = described_class.find(fixture[:advisory].id)
          child = SecurityAdvisoryUpdate.find(update.id)
          child.security_advisory
          ready << true
          resume.pop
          case operation
          when :correction
            advisory.update_content!({ name: 'Too late' }, expected_content_revision: 0)
          when :update_creation
            advisory.create_update!({}, { SpecSeed.language => { summary: 'Too late' } })
          when :update_translation
            child.update_translations!(SpecSeed.language => { summary: 'Too late' })
          end
        end
      rescue ActiveRecord::RecordNotFound
        :missing
      end
      Timeout.timeout(10) { ready.pop }
      connection_thread { described_class.find(fixture[:advisory].id).destroy_content!(expected_content_revision: 0) }.value
      resume << true
      expect(Timeout.timeout(20) { worker.value }).to eq(:missing)
      expect(described_class.where(id: fixture[:advisory].id)).to be_empty
      expect(SecurityAdvisoryUpdate.where(security_advisory_id: fixture[:advisory].id)).to be_empty
      expect(SecurityAdvisoryTranslation.where(security_advisory_update_id: update.id)).to be_empty
    ensure
      resume << true if resume
      finish_threads(worker)
    end
  end

  it 'rereads a deleted update child under the parent lock before writing translations' do
    update = connection_thread do
      described_class.find(fixture[:advisory].id).create_update!({}, { SpecSeed.language => { summary: 'Original' } })
    end.value
    ready = Queue.new
    resume = Queue.new
    worker = connection_thread do
      SecurityAdvisoryUpdate.transaction do
        child = SecurityAdvisoryUpdate.find(update.id)
        child.security_advisory
        ready << true
        resume.pop
        child.update_translations!(SpecSeed.language => { summary: 'Too late' })
      end
    rescue ActiveRecord::RecordNotFound
      :missing
    end
    Timeout.timeout(10) { ready.pop }
    connection_thread do
      described_class.find(fixture[:advisory].id).with_lock { SecurityAdvisoryUpdate.find(update.id).destroy! }
    end.value
    resume << true
    expect(Timeout.timeout(20) { worker.value }).to eq(:missing)
    expect(SecurityAdvisoryTranslation.where(security_advisory_update_id: update.id)).to be_empty
  ensure
    resume << true if resume
    finish_threads(worker)
  end
end
