module NodeCtl
  class Commands::Chain < Command::Remote
    cmd :chain
    args '<chain> <command>'
    description 'List transaction confirmations and run them'

    def options(parser, args)
      self.opts = {
        direction: :execute,
        success: true,
      }

      parser.separator <<END
Subcommands:
confirmations [TRANSACTION]...  List transaction confirmations
confirm [TRANSACTION]...        Run transaction confirmations
release [locks|ports]           Release acquired locks and reserved ports
resolve                         Mark the chain as resolved
END

      return if args[1] != 'confirm'

      parser.on(
        '--direction DIR',
        %w(execute rollback),
        'Direction (execute or rollback)'
      ) do |d|
        opts[:direction] = d
      end

      parser.on('--[no-]success', 'Success') do |s|
        opts[:success] = s
      end
    end

    def validate
      if args.size < 2
        raise ValidationError, 'arguments missing'

      elsif /\A\d+\z/ !~ args[0]
        raise ValidationError, "invalid chain id '#{args[0]}'"

      elsif !%w(confirmations confirm release resolve).include?(args[1])
        raise ValidationError, "invalid subcommand '#{args[1]}'"
      end

      params.update({
        chain: args[0].to_i,
        command: args[1],
        transactions: args.size > 2 ? args[2..-1].map { |v| v.to_i } : nil,
      })

      case args[1]
      when 'confirm'
        params.update({
          direction: opts[:direction],
          success: opts[:success],
        })

      when 'release'
        if args[2] && !%w(locks ports).include?(args[2])
          raise ValidationError, "invalid resource '#{args[2]}'"
        end

        params.update({
          release: args[2].nil? ? %w(locks ports) : [args[2]],
        })
      end
    end

    def process
      case args[1]
      when 'confirmations'
        list_confirmations(response[:transactions])

      when 'confirm'
        list_confirmations(response[:transactions])

      when 'release'
        list_locks(response[:locks]) if response[:locks]
        list_ports(response[:ports]) if response[:ports]
      end

      nil
    end

    protected
    def list_confirmations(list)
      list.each do |t, confirmations|
        puts "TRANSACTION ##{t}"
        puts sprintf(
          "%-6s %-13s %-4s %-20s %-12s %s",
          'ID', 'TYPE', 'DONE', 'OBJECT', 'ID', 'ATTRS'
        )

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

