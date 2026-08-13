require 'securerandom'

module VpsAdmin::API::Tasks
  class Dns < Base
    DAYS = ENV['DAYS'] ? ENV['DAYS'].to_i : 365

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

    def prune_transfer_logs
      cnt = ::DnsServerZoneTransferLog.prune!(days: DAYS)
      puts "Deleted #{cnt} DNS transfer logs"
    end

    # Destructively start a new event generation. DNS-zone writers, nodectld
    # producers and transfer-log consumers have to be stopped by the operator.
    # The queued refresh chains are consumed only after new nodectld starts.
    def reset_primary_transfer_tracking
      refresh_configuration = ENV.fetch('REFRESH_CONFIGURATION', '1')
      unless %w[0 1].include?(refresh_configuration)
        raise 'REFRESH_CONFIGURATION has to be 0 or 1'
      end

      state_count = 0
      log_count = 0
      tracked_zone_count = 0

      ::DnsZone.transaction do
        state_count = ::DnsServerZonePrimaryTransferState.delete_all
        log_count = ::DnsServerZoneTransferLog.delete_all
        clear_latest_transfer_fields

        ::DnsZone.find_each do |zone|
          if zone.enabled? && zone.external_source?
            zone.update_columns(
              primary_transfer_tracking_started_at: Time.current,
              primary_transfer_generation: SecureRandom.uuid
            )
            tracked_zone_count += 1
          else
            zone.update_columns(
              primary_transfer_tracking_started_at: nil,
              primary_transfer_generation: nil
            )
          end
        end
      end

      refresh_count = if refresh_configuration == '1'
                        enqueue_configuration_refreshes
                      else
                        0
                      end

      puts "Deleted #{log_count} DNS transfer logs"
      puts "Deleted #{state_count} DNS primary transfer path states"
      puts "Started a fresh tracking generation for #{tracked_zone_count} DNS zones"
      if refresh_configuration == '1'
        puts "Queued #{refresh_count} DNS server-zone configuration refreshes"
      else
        puts 'Skipped DNS server-zone configuration refreshes'
      end
    end

    # Refuse a rollback while a new-format server-zone update can still be
    # delivered to an old nodectld. Run while the new nodectld fleet is still
    # available to finish its configuration queue.
    def verify_primary_transfer_configuration_drained
      count = pending_primary_transfer_configuration_transactions.count

      if count > 0
        raise "#{count} new-format DNS server-zone configuration transactions are still pending"
      end

      puts 'No new-format DNS server-zone configuration transactions are pending'
    end

    # Establish an empty DNS configuration queue before switching nodectld
    # payload formats. DNS-zone writers have to be stopped first.
    def verify_configuration_drained
      count = pending_dns_configuration_transactions.count

      if count > 0
        raise "#{count} DNS configuration transaction chains are still pending"
      end

      puts 'No DNS configuration transaction chains are pending'
    end

    protected

    def pending_primary_transfer_configuration_transactions
      ::TransactionChain
        .joins(:transactions)
        .where('transactions.input LIKE ?', '%"primary_transfer_generation":%')
        .where(
          'transaction_chains.state IN (:chain_states) OR transactions.done IN (:transaction_states)',
          chain_states: ::TransactionChain.states.values_at('queued', 'rollbacking'),
          transaction_states: ::Transaction.dones.values_at('waiting', 'staged')
        )
        .distinct
    end

    def pending_dns_configuration_transactions
      ::TransactionChain
        .joins(:transactions)
        .where(transactions: { queue: 'dns' })
        .where(
          'transaction_chains.state IN (:chain_states) OR transactions.done IN (:transaction_states)',
          chain_states: ::TransactionChain.states.values_at('queued', 'rollbacking'),
          transaction_states: ::Transaction.dones.values_at('waiting', 'staged')
        )
        .distinct
    end

    def clear_latest_transfer_fields
      ::DnsServerZone.update_all(
        last_transfer_log_id: nil,
        last_transfer_at: nil,
        last_transfer_status: nil,
        last_transfer_reason_code: nil,
        last_transfer_reason: nil,
        last_transfer_primary_addr: nil,
        last_transfer_serial: nil
      )
    end

    def enqueue_configuration_refreshes
      count = 0
      ::DnsServerZone.existing.includes(:dns_server, dns_zone: :dns_zone_transfers).find_each do |server_zone|
        TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone)
        count += 1
      end
      count
    end
  end
end
