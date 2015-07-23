module VpsAdmindCtl::Commands
  class Chain < VpsAdmindCtl::Command
    args '<chain> <command>'
    description 'List transaction confirmations and run them'

    def options(opts, args)
      @opts = {
          direction: :execute,
          success: true
      }

      opts.separator <<END
Subcommands:
confirmations [TRANSACTION]...  List transaction confirmations
confirm [TRANSACTION]...        Run transaction confirmations
END
    
      if args[1] == 'confirm'
        opts.on('--direction DIR', %w(execute rollback), 'Direction (execute or rollback)') do |d|
          @opts[:direction] = d
        end

        opts.on('--[no]-success', 'Success') do |s|
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

      unless %w(confirmations confirm).include?(@args[2])
        raise VpsAdmindCtl::ValidationError, "invalid subcommand '#{@args[2]}'"
      end

      ret = {
          :chain => @args[1].to_i,
          :command => @args[2],
          :transactions => @args.size > 3 ? @args[3..-1].map { |v| v.to_i } : nil
      }

      if @args[2] == 'confirm'
        ret.update({
            :direction => @opts[:direction],
            :success => @opts[:success]
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
            format_hash(c[:attr_changes]),
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
  end
end

