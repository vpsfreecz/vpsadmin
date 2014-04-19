module Commands
  class Show < Command
    args '<command>'
    description 'Show vpsAdmind internals'

    def options(opts, args)

    end

    def validate
      if ARGV.size < 2
        raise ValidationError.new('missing resource')
      end

      {:resource => ARGV[1]}
    end

    def process
      case ARGV[1]
        when 'config'
          cfg = @res['config']

          if ARGV[2]
            ARGV[2].split('.').each do |s|
              cfg = cfg[cfg.instance_of?(Array) ? s.to_i : s]
            end
          end

          if @global_opts[:parsable]
            puts cfg.to_json
          else
            pp cfg
          end

        when 'queue'
          q = @res['queue']

          if @global_opts[:parsable]
            puts q.to_json
          else
            puts sprintf(
              '%-8s %-3s %-4s %-5s %-5s %-5s %-8s %-18.16s',
              'TRANS', 'URG', 'PRIO', 'USER', 'VEID', 'TYPE', 'DEP', 'WAITING'
            )

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
