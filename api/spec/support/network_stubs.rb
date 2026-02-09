# frozen_string_literal: true

module SpecNetworkStubs
  module DnsStub
    def get_ptr(_ip)
      ''
    end
  end
end

RSpec.configure do |config|
  config.before do
    dns_klass = ::VpsAdmin::API::Operations::Utils::Dns
    dns_klass.prepend(SpecNetworkStubs::DnsStub) unless dns_klass < SpecNetworkStubs::DnsStub
  rescue NameError
    # ignore
  end
end
