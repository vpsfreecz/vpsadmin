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
    submission = result.submission

    expect(result).to be_accepted
    expect(submission.identifier.length).to eq(127)
    expect(submission.user_agent.length).to eq(described_class::USER_AGENT_LIMIT)
    expect(submission.client_ip_addr).to eq('203.0.113.1')
  end

  it 'uses a queue capacity of one hundred unfinished submissions' do
    expect(described_class::MAX_PENDING).to eq(100)
  end
end
