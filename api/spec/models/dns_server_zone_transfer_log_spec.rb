# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DnsServerZoneTransferLog do
  it 'requires every post-cutover log to identify its attempt kind' do
    log = described_class.new(
      dns_server_zone: create_dns_server_zone!(
        dns_zone: create_dns_zone!(user: SpecSeed.user),
        dns_server: create_dns_server!(node: SpecSeed.node)
      ),
      event_key: SecureRandom.hex(32),
      event_at: Time.current,
      status: :failed
    )

    expect(log).not_to be_valid
    expect(log.errors.of_kind?(:attempt_kind, :blank)).to be(true)
  end
end
