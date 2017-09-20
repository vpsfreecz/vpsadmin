module VpsAdmindCtl::Commands
  class Chain < VpsAdmindCtl::Command
    args '<chain> <command>'
    description 'List transaction confirmations and run them'

    def options(opts, args)
      @opts = {
          :direction => :execute,
          :success => true
      }

      opts.separator <<END
Subcommands:
confirmations [TRANSACTION]...  List transaction confirmations
confirm [TRANSACTION]...        Run transaction confirmations
release [locks|ports]           Release acquired locks and reserved ports
END
    
      if args[1] == 'confirm'
        opts.on('--direction DIR', %w(execute rollback), 'Direction (execute or rollback)') do |d|
          @opts[:direction] = d
        end
        
        opts.on('--[no-]success', 'Success') do |s|
          @opts[:success] = s
        end
      end
    end

    def validate 
      if ARGV.size < 3
        raise VpsAdmindCtl::ValidationError, 'arguments missing'
      end

      unless /\A\d+\z/ =~ @args[1]
        raise VpsAdmindCtl::ValidationError, "invalid chain id '#{@args[1]}'"
      end

      unless %w(confirmations confirm release).include?(@args[2])
        raise VpsAdmindCtl::ValidationError, "invalid subcommand '#{@args[2]}'"
      end

      ret = {
          :chain => @args[1].to_i,
          :command => @args[2],
          :transactions => @args.size > 3 ? @args[3..-1].map { |v| v.to_i } : nil
      }

      case @args[2]
        when 'confirm'
          ret.update({
              :direction => @opts[:direction],
              :success => @opts[:success]
          })

        when 'release'
          if @args[3] && !%w(locks ports).include?(@args[3])
            raise VpsAdmindctl::ValidationError, "invalid resource '#{@args[3]}'"
          end

          ret.update({
              :release => @args[3].nil? ? %w(locks ports) : [@args[3]]
          })
      end

      ret
    end

    def process
      case @args[2]
        when 'confirmations'
          list_confirmations(@res[:transactions])

        when 'confirm'
          list_confirmations(@res[:transactions])

        when 'release'
          list_locks(@res[:locks]) if @res[:locks]
          list_ports(@res[:ports]) if @res[:ports]

      end
    end

    def list_confirmations(list)
      list.each do |t, confirmations|
        puts "TRANSACTION ##{t}"
        puts sprintf("%-6s %-13s %-4s %-20s %-12s %s",
                    'ID', 'TYPE', 'DONE', 'OBJECT', 'ID', 'ATTRS')

        confirmations.each do |c|
          puts sprintf(
            '%-6d %-13s %-4s %-20s %-12s %s',
            c[:id],
            c[:type],
            c[:done] ? 1 : 0,
            c[:class_name],
            format_hash(c[:row_pks]),
            format_hash(c[:attr_changes])
          )
        end
        puts '-' * 80
      end
    end

    def format_hash(hash)
      return '' unless hash
      return hash if hash.is_a?(::String)
      hash.inject([]) { |s, v| s << v.join('=')  }.join(',')
    end

    def list_locks(locks)
      puts "RESOURCE LOCKS"
      puts sprintf('%-30s %-10s %-20s', 'RESOURCE', 'ROW_ID', 'LOCKED_AT')

      locks.each do |l|
        puts sprintf('%-30s %-10d %-20s', l[:resource], l[:row_id], l[:created_at])
      end

      puts "Released #{locks.count} locks"
    end

    def list_ports(ports)
      puts "RESERVED PORTS"
      puts sprintf('%-20s %-20s %-10s', 'NODE', 'ADDR', 'PORT')

      ports.each do |p|
        puts sprintf(
            '%-20s %-20s %-10d',
            "#{p[:node_name]}.#{p[:location_domain]}",
            p[:addr],
            p[:port]
        )
      end

      puts "Released #{ports.count} ports"
    end
  end
end

