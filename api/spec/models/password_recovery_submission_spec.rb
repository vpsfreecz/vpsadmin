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

  it 'bounds queued requests per source without using the identifier' do
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

    expect(first).to be_present
    expect(second).to be_nil
    expect(described_class.count).to eq(1)
  end

  it 'applies exact global backpressure across sources' do
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

    expect(first).to be_present
    expect(second).to be_nil
    expect(described_class.count).to eq(1)
  end

  it 'bounds stored payloads and uses the proxy source address' do
    submission = described_class.enqueue!(
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

    expect(submission.identifier.length).to eq(127)
    expect(submission.user_agent.length).to eq(described_class::USER_AGENT_LIMIT)
    expect(submission.client_ip_addr).to eq('203.0.113.1')
  end
end
