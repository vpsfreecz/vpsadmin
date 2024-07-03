module Transactions::DnsServer
  class Reload < ::Transaction
    t_name :dns_server_reload
    t_type 5510
    queue :dns

    def params(dns_server, zone: nil)
      self.node_id = dns_server.node_id

      { zone: }
    end
  end
end
