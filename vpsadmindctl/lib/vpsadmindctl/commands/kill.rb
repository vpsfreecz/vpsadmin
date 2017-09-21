module VpsAdmindCtl::Commands
  class Kill < VpsAdmindCtl::Command
    args '[ID|TYPE]...'
    description 'Kill transaction(s) that are being processed'

    def options(opts, args)
      @opts = {
          :all => false,
          :type => nil,
      }

      opts.on('-a', '--all', 'Kill all transactions') do
        @opts[:all] = true
      end
      opts.on('-t', '--type', 'Kill all transactions of this type') do
        @opts[:type] = true
      end
    end

    def validate
      if @opts[:all]
        {:transactions => :all}

      elsif @opts[:type]
        if ARGV.size < 2
          raise VpsAdmindCtl::ValidationError.new('missing transaction type(s)')
        end

        {:types => ARGV[1..-1]}

      else
        if ARGV.size < 2
          raise VpsAdmindCtl::ValidationError.new('missing transaction id(s)')
        end

        {:transactions => ARGV[1..-1]}
      end
    end

    def process
      @res[:msgs].each do |i, msg|
        puts "#{i}: #{msg}"
      end

      puts '' if @res[:msgs].size > 0

      puts "Killed #{@res[:killed]} transactions"
    end
  end
end
