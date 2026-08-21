# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PasswordRecoverySubmission do
  before do
    SysConfig.find_or_create_by!(category: 'core', name: 'password_recovery_enabled')
             .update!(value: true)
  end

  def request(ip:, user_agent: 'Password recovery submission spec', extra_env: {})
    build_request(ip:, user_agent:, extra_env:)
  end

  it 'rate-limits a normalized submitted value without resolving an account' do
    first = described_class.enqueue!(
      identifier: '  Member@Example.Test  ',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1')
    )
    second = described_class.enqueue!(
      identifier: 'member@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.2')
    )

    expect(first).to be_accepted
    expect(first.submission.identifier).to eq('Member@Example.Test')
    expect(first.submission.identifier_digest).to eq(
      Digest::SHA256.hexdigest('member@example.test')
    )
    expect(second).to be_rate_limited
    expect(second.retry_after).to be_between(1, described_class::IDENTIFIER_INTERVAL.to_i)
    expect(described_class.count).to eq(1)
    expect(
      PasswordEventCounter.find_by!(name: 'password_recovery_submission_accepted').event_count
    ).to eq(1)
    expect(
      PasswordEventCounter.find_by!(name: 'password_recovery_submission_rate_limited').event_count
    ).to eq(1)
  end

  it 'bounds accepted requests per source across submitted values' do
    stub_const("#{described_class}::MAX_PER_SOURCE", 1)

    first = described_class.enqueue!(
      identifier: 'known@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1')
    )
    second = described_class.enqueue!(
      identifier: 'unknown@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1')
    )

    expect(first).to be_accepted
    expect(second).to be_rate_limited
    expect(second.retry_after).to be_between(1, described_class::SOURCE_INTERVAL.to_i)
    expect(described_class.count).to eq(1)
  end

  it 'limits unfinished work without counting finished throttle ledgers' do
    stub_const("#{described_class}::MAX_PENDING", 1)

    first = described_class.enqueue!(
      identifier: 'first@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1')
    )
    second = described_class.enqueue!(
      identifier: 'second@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.2')
    )

    expect(first).to be_accepted
    expect(second).to be_busy
    expect(
      PasswordEventCounter.find_by!(name: 'password_recovery_queue_capacity_reached').event_count
    ).to eq(1)
    expect(
      PasswordEventCounter.find_by!(name: 'password_recovery_submission_queue_full').event_count
    ).to eq(1)

    first.submission.finish!
    third = described_class.enqueue!(
      identifier: 'third@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.3')
    )

    expect(third).to be_accepted
    expect(described_class.pending.count).to eq(1)
    expect(described_class.count).to eq(2)
    expect(
      PasswordEventCounter.find_by!(name: 'password_recovery_queue_capacity_reached').event_count
    ).to eq(2)
  end

  it 'keeps a finished digest for throttling and clears queued payload data' do
    result = described_class.enqueue!(
      identifier: 'finished@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1', user_agent: 'Sensitive agent')
    )

    result.submission.finish!
    finished = result.submission.reload

    expect(finished.finished_at).to be_present
    expect(finished.identifier).to be_nil
    expect(finished.user_agent).to be_nil
    expect(described_class.claimable).not_to include(finished)

    repeated = described_class.enqueue!(
      identifier: 'FINISHED@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.2')
    )
    expect(repeated).to be_rate_limited
  end

  it 'finishes a stale final claim after a worker is terminated' do
    stub_const("#{described_class}::MAX_PENDING", 1)
    result = described_class.enqueue!(
      identifier: 'terminated@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.1', user_agent: 'Terminated worker')
    )
    result.submission.update!(
      attempts: described_class::MAX_ATTEMPTS,
      processing_started_at: described_class::CLAIM_TIMEOUT.ago - 1.second
    )

    expect(described_class.claim_next).to be_nil

    finished = result.submission.reload
    expect(finished.finished_at).to be_present
    expect(finished.identifier).to be_nil
    expect(finished.user_agent).to be_nil

    replacement = described_class.enqueue!(
      identifier: 'replacement@example.test',
      locale: :en,
      oauth2_client: nil,
      request: request(ip: '192.0.2.2')
    )
    expect(replacement).to be_accepted
  end

  it 'bounds stored payloads and uses the proxy source address' do
    result = nil
    expect do
      result = described_class.enqueue!(
        identifier: "  #{'a' * 200}  ",
        locale: :en,
        oauth2_client: nil,
        request: request(
          ip: '192.0.2.1',
          user_agent: 'u' * 1_000,
          extra_env: {
            'HTTP_CLIENT_IP' => '198.51.100.1',
            'HTTP_X_REAL_IP' => '203.0.113.1'
          }
        )
      )
    end.not_to change(UserAgent, :count)
    submission = result.submission

    expect(result).to be_accepted
    expect(submission.identifier.length).to eq(127)
    expect(submission.user_agent.length).to eq(described_class::USER_AGENT_LIMIT)
    expect(submission.client_ip_addr).to eq('203.0.113.1')
  end

  it 'uses a queue capacity of one hundred unfinished submissions' do
    expect(described_class::MAX_PENDING).to eq(100)
  end

  # The worker thread needs a committed fixture outside the per-example
  # transaction in spec_helper so its independent connection can see it.
  # rubocop:disable RSpec/LeakyLocalVariable
  queue_serialization_state = {}

  describe 'queue admission serialization' do
    before(:context) do
      config = SysConfig.find_by!(
        category: 'core',
        name: 'password_recovery_enabled'
      )
      queue_serialization_state[:previous_recovery_enabled] = config.value
      config.update!(value: true)
      queue_serialization_state[:submission] = described_class.create!(
        identifier: 'serialized@example.test',
        identifier_digest: Digest::SHA256.hexdigest('serialized@example.test'),
        locale: 'en'
      )
    end

    after(:context) do
      queue_serialization_state[:submission].destroy!
      SysConfig.find_by!(
        category: 'core',
        name: 'password_recovery_enabled'
      ).update!(value: queue_serialization_state[:previous_recovery_enabled])
    end

    it 'serializes worker completion with admission capacity accounting' do
      lock_acquired = Queue.new
      release_lock = Queue.new
      finish_started = Queue.new
      finished_at = Queue.new
      errors = Queue.new

      lock_holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.with_queue_lock do
            lock_acquired << true
            release_lock.pop
          end
        end
      rescue StandardError => e
        errors << e
      end
      lock_acquired.pop

      finisher = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          submission = described_class.find(queue_serialization_state[:submission].id)
          finish_started << true
          submission.finish!
          finished_at << submission.finished_at
        end
      rescue StandardError => e
        errors << e
      end
      finish_started.pop

      begin
        expect(finisher.join(0.2)).to be_nil
      ensure
        release_lock << true
        lock_holder.join
        finisher.join
      end

      raise errors.pop unless errors.empty?

      expect(finished_at.pop).to be_present
    end
  end

  cleanup_serialization_state = {}

  describe 'retention cleanup serialization' do
    before(:context) do
      config = SysConfig.find_by!(
        category: 'core',
        name: 'password_recovery_enabled'
      )
      cleanup_serialization_state[:previous_recovery_enabled] = config.value
      config.update!(value: true)
      cleanup_serialization_state[:submission] = described_class.create!(
        identifier: 'stale-serialized@example.test',
        identifier_digest: Digest::SHA256.hexdigest('stale-serialized@example.test'),
        locale: 'en',
        created_at: described_class::RECORD_RETENTION.ago - 1.minute
      )
    end

    after(:context) do
      described_class.where(id: cleanup_serialization_state[:submission].id).delete_all
      SysConfig.find_by!(
        category: 'core',
        name: 'password_recovery_enabled'
      ).update!(value: cleanup_serialization_state[:previous_recovery_enabled])
    end

    it 'serializes pending retention cleanup with queue admission' do
      lock_acquired = Queue.new
      release_lock = Queue.new
      cleanup_started = Queue.new
      submission_exists = Queue.new
      errors = Queue.new

      lock_holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.with_queue_lock do
            lock_acquired << true
            release_lock.pop
          end
        end
      rescue StandardError => e
        errors << e
      end
      lock_acquired.pop

      cleaner = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          cleanup_started << true
          described_class.destroy_stale!(before: Time.current)
          submission_exists << described_class.exists?(
            cleanup_serialization_state[:submission].id
          )
        end
      rescue StandardError => e
        errors << e
      end
      cleanup_started.pop

      begin
        expect(cleaner.join(0.2)).to be_nil
      ensure
        release_lock << true
        lock_holder.join
        cleaner.join
      end

      raise errors.pop unless errors.empty?

      expect(submission_exists.pop).to be(false)
    end
  end
  # rubocop:enable RSpec/LeakyLocalVariable
end
