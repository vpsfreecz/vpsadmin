module Commands
  class Get < Command
    args '<command>'
    description 'Get vpsAdmind resources and properties'

    def options(opts, args)
      @opts = {
          :header => true,
          :limit => 50,
      }

      opts.on('-H', '--no-header', 'Suppress header row') do
        @opts[:header] = false
      end

      opts.on('-l', '--limit LIMIT', Integer, 'Limit number of items to get') do |l|
        @opts[:limit] = l
      end
    end

    def validate
      if ARGV.size < 2
        raise ValidationError.new('missing resource')
      end

      {:resource => @args[1], :limit => @opts[:limit]}
    end

    def process
      case @args[1]
        when 'config'
          cfg = @res[:config]

          if @args[2]
            @args[2].split('.').each do |s|
              cfg = cfg[cfg.instance_of?(Array) ? s.to_i : s.to_sym]
            end
          end

          if @global_opts[:parsable]
            puts cfg.to_json
          else
            pp cfg
          end

        when 'queue'
          q = @res[:queue]

          if @global_opts[:parsable]
            puts q.to_json
          else
            puts sprintf(
              '%-8s %-3s %-4s %-5s %-5s %-5s %-8s %-18.16s',
              'TRANS', 'URG', 'PRIO', 'USER', 'VEID', 'TYPE', 'DEP', 'WAITING'
            ) if @opts[:header]

            q.each do |t|
              puts sprintf(
                  '%-8d %-3d %-4d %-5d %-5d %-5d %-8d %-18.16s',
                  t['id'], t['urgent'] ? 1 : 0, t['priority'], t['m_id'], t['vps_id'],
                  t['type'], t['depends_on'],
                  format_duration(Time.new.to_i - t['time'])
              )
            end
          end

        else
          pp @res
      end

      nil
    end
  end
end
