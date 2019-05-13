module VpsAdmin::API
  module Operations::Utils::Dns
    # @param ip [String]
    # @return [String]
    def get_ptr(ip)
      Resolv.new.getname(ip)
    rescue Resolv::ResolvError => e
      e.message
    end
  end
end
