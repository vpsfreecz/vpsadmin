module VpsAdmin::API::Tasks
  class Dns < Base
    # Check that DNS servers return the configured reverse records
    #
    # Accepts the following environment variables:
    # [SERVERS]: check only listed server names, separated by commas
    def check_reverse_records
      cnt_success = 0
      cnt_fail = 0
      cnt_incorrect = 0
      servers = ENV['SERVERS'] ? ENV['SERVERS'].split(',') : nil

      ::HostIpAddress
        .includes(reverse_dns_record: { dns_zone: { dns_server_zones: :dns_server } })
        .where.not(reverse_dns_record: nil)
        .each do |host_ip|
        host_ip.reverse_dns_record.dns_zone.dns_server_zones.each do |server_zone|
          next if servers && !servers.include?(server_zone.dns_server.name)

          ptr = nil

          VpsAdmin::API::DnsResolver.open([server_zone.dns_server.ipv4_addr]) do |dns|
            3.times do
              ptr = dns.query_ptr(host_ip.ip_addr)
              break
            rescue Resolv::ResolvError
              sleep(1)
              next
            end
          end

          if ptr.nil?
            warn "#{host_ip.ip_addr}: failed to get reverse record from #{server_zone.dns_server.name}"
            cnt_fail += 1
            next
          end

          if ptr != host_ip.reverse_dns_record.content
            warn "#{host_ip.ip_addr}: #{server_zone.dns_server.name} returned #{ptr.inspect}, " \
                 "expected #{host_ip.reverse_dns_record.content.inspect}"
            cnt_incorrect += 1
            next
          end

          cnt_success += 1
        end
      end

      puts "#{cnt_success} records ok"
      puts "#{cnt_fail} dns errors"
      puts "#{cnt_incorrect} records incorrect"
      exit(false) if cnt_fail > 0 || cnt_incorrect > 0
    end
  end
end
