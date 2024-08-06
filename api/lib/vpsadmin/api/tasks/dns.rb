module VpsAdmin::API::Tasks
  class Dns < Base
    def check_reverse_records
      cnt_success = 0
      cnt_fail = 0
      cnt_incorrect = 0

      ::HostIpAddress
        .includes(reverse_dns_record: { dns_zone: :dns_server_zones })
        .where.not(reverse_dns_record: nil)
        .each do |host_ip|
        host_ip.reverse_dns_record.dns_zone.dns_server_zones.each do |server_zone|
          dig = nil
          success = false
          cmd = "dig -x #{host_ip.ip_addr} @#{server_zone.dns_server.ipv4_addr} +short"

          3.times do
            dig = `#{cmd}`.strip

            case $?.exitstatus
            when 0
              success = true
              break
            when 9
              sleep(1)
              next
            else
              break
            end
          end

          unless success
            warn "#{host_ip.ip_addr}: failed to get reverse record from #{server_zone.dns_server.name}"
            cnt_fail += 1
            next
          end

          if dig != host_ip.reverse_dns_record.content
            warn "#{host_ip.ip_addr}: #{server_zone.dns_server.name} returned #{dig.inspect}, " \
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
