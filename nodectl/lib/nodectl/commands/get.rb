require 'ipaddr'

module NodeCtl
  class Commands::Get < Command::Remote
    cmd :get
    args '<command>'
    description 'Get nodectld resources and properties'

    include Utils

    def options(parser, args)
      opts.update({
          header: true,
          limit: 50,
      })

      parser.on('-H', '--no-header', 'Suppress header row') do
        opts[:header] = false
      end

      parser.on('-l', '--limit LIMIT', Integer, 'Limit number of items to get') do |l|
        opts[:limit] = l
      end

      parser.separator <<END

Subcommands:
config [some.key]    Show nodectld's config or specific key
queue                List transactions queued for execution
ip_map               Print hash table that maps IP addresses to their IDs
END
    end

    def validate
      raise ValidationError, 'missing resource' if args.size < 1

      params.update({resource: args[0], limit: opts[:limit]})
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
          puts sprintf(
            '%-6s %-8s %-3s %-3s %-4s %-5s %-5s %-5s %-8s %-18.16s',
            'CHAIN', 'TRANS', 'DIR', 'URG', 'PRIO', 'USER', 'VEID', 'TYPE', 'DEP', 'WAITING'
          ) if opts[:header]

          q.each do |t|
            puts sprintf(
              '%-6d %-8d %-3d %-3d %-4d %-5d %-5d %-5d %-8d %-18.16s',
              t[:chain], t[:id], t[:state], t[:urgent] ? 1 : 0, t[:priority], t[:m_id], t[:vps_id],
              t[:type], t[:depends_on],
              format_duration(Time.new.to_i - t[:time])
            )
          end
        end

      when 'ip_map'
        map = response[:ip_map]

        if global_opts[:parsable]
          puts map.to_json

        else
          puts sprintf(
            '%-40s %8s %8s',
            'ADDR', 'ID', 'USER'
          ) if opts[:header]

          map.sort do |a, b|
            IPAddr.new(a[0].to_s).to_i <=> IPAddr.new(b[0].to_s).to_i

          end.each do |ip, opts|
            puts sprintf(
              '%-40s %8s %8s',
              ip, opts[:id], opts[:user_id]
            )
          end
        end

      else
        pp response
      end

      nil
    end
  end
end
