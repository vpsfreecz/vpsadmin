require 'resolv'

module VpsAdmin::API
  # Lightweight wrapper of Resolv
  class DnsResolver
    def self.open(*, **)
      dns = new(*, **)
      ret = yield(dns)
      dns.close
      ret
    end

    # @param nameservers [Array(String)]
    # @param timeout [Integer]
    def initialize(nameservers, timeout: 5)
      @dns = Resolv::DNS.open(nameserver: nameservers, search: [], ndots: 1)
      @dns.timeouts = timeout
    end

    def close
      @dns.close
    end

    # @param name [String]
    # @return [Resolv::DNS::Resource::IN::SOA]
    def query_soa(name)
      @dns.getresources(name, Resolv::DNS::Resource::IN::SOA)
    end

    # @param address [String]
    # @return [String]
    # @raise [Resolv::ResolvError]
    def query_ptr(address)
      "#{@dns.getname(address)}."
    end
  end
end
