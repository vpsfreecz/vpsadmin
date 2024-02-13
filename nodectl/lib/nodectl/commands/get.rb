require 'ipaddr'
require 'libosctl'

module NodeCtl
  class Commands::Get < Command::Remote
    cmd :get
    args '<command>'
    description 'Get nodectld resources and properties'

    include Utils
    include OsCtl::Lib::Utils::Humanize

    def options(parser, _args)
      opts.update({
                    header: true,
                    limit: 50
                  })

      parser.on('-H', '--no-header', 'Suppress header row') do
        opts[:header] = false
      end

      parser.on('-l', '--limit LIMIT', Integer, 'Limit number of items to get') do |l|
        opts[:limit] = l
      end

      parser.separator <<~END

        Subcommands:
        config [some.key]    Show nodectld's config or specific key
        queue                List transactions queued for execution
        veth_map             Print hash table that maps VPS interfaces to host interfaces
        net_accounting       Print network interface accounting state
      END
    end

    def validate
      raise ValidationError, 'missing resource' if args.empty?

      params.update({ resource: args[0], limit: opts[:limit] })
    end

    def process
      case args[0]
      when 'config'
        cfg = response[:config]

        if args[1]
          args[1].split('.').each do |s|
            cfg = cfg[cfg.instance_of?(Array) ? s.to_i : s.to_sym]
          end
        end

        if global_opts[:parsable]
          puts cfg.to_json

        else
          pp cfg
        end

      when 'queue'
        q = response[:queue]

        if global_opts[:parsable]
          puts q.to_json

        else
          if opts[:header]
            puts format(
              '%-6s %-8s %-3s %-3s %-4s %-5s %-5s %-5s %-8s %-18.16s',
              'CHAIN', 'TRANS', 'DIR', 'URG', 'PRIO', 'USER', 'VEID', 'TYPE', 'DEP', 'WAITING'
            )
          end

          q.each do |t|
            puts format(
              '%-6d %-8d %-3d %-3d %-4d %-5d %-5d %-5d %-8d %-18.16s',
              t[:chain], t[:id], t[:state], t[:urgent] ? 1 : 0, t[:priority], t[:m_id], t[:vps_id],
              t[:type], t[:depends_on],
              format_duration(Time.new.to_i - t[:time])
            )
          end
        end

      when 'veth_map'
        map = response[:veth_map]

        if global_opts[:parsable]
          puts map.to_json

        else
          if opts[:header]
            puts format(
              '%-10s %s',
              'VPS', 'INTERFACES'
            )
          end

          map.sort do |a, b|
            a[0] <=> b[0]
          end.each do |vps_id, netifs|
            puts format(
              '%-10s %s',
              vps_id,
              netifs.map { |vps_veth, host_veth| "#{vps_veth}=#{host_veth}" }.join(',')
            )
          end
        end

      when 'net_accounting'
        interfaces = response[:interfaces]

        if global_opts[:parsable]
          puts interfaces.to_json

        else
          if opts[:header]
            puts format( # rubocop:disable Lint/FormatParameterMismatch
              "%-10s %5s %-10s %8s %8s %8s %6s #{(['%12s'] * 4 * 3).join(' ')}",
              'VPS', 'USER', 'NETIF', 'NETIF_ID',
              'UPDATE', 'LOG', 'DELTA',
              'B/IN', 'B/OUT', 'PKT/IN', 'PKT/OUT',
              'LOG_B/IN', 'LOG_B/OUT', 'LOG_PKT/IN', 'LOG_PKT/OUT',
              'LAST_B/IN', 'LAST_B/OUT', 'LAST_PKT/IN', 'LAST_PKT/OUT'
            )
          end

          row_fmt = "%-10d %5d %-10s %8d %8s %8s %6d #{(['%12s'] * 4 * 3).join(' ')}"
          now = Time.now

          interfaces.each do |n|
            puts format(
              row_fmt,
              n[:vps_id],
              n[:user_id],
              n[:vps_name],
              n[:netif_id],
              n[:last_update] ? format_duration_ago(n[:last_update], now) : '-',
              n[:last_log] ? format_duration_ago(n[:last_log], now) : '-',
              n[:delta],
              *format_interface_stats(n, ''),
              *format_interface_stats(n, 'log_'),
              *format_interface_stats(n, 'last_')
            )
          end
        end
      else
        pp response
      end

      nil
    end

    protected

    def format_duration_ago(timestamp, from)
      format('-%.1fs', from - Time.at(timestamp))
    end

    def format_interface_stats(n, prefix)
      [
        humanize_data(n[:"#{prefix}bytes_in"]),
        humanize_data(n[:"#{prefix}bytes_out"]),
        humanize_number(n[:"#{prefix}packets_in"]),
        humanize_number(n[:"#{prefix}packets_out"])
      ]
    end
  end
end
