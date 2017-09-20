module VpsAdmindCtl::CommandTemplates
  class ResourceControl < VpsAdmindCtl::Command
    args 'all|fw|shaper'

    def validate
      raise VpsAdmindCtl::ValidationError.new('missing resource') if @args.size < 2
      raise VpsAdmindCtl::ValidationError.new('not a valid resource') unless %w(all fw shaper).include?(@args[1])

      {:resources => @args[1] == 'all' ? [:fw, :shaper] : [@args[1]]}
    end

    def process
      @res.each do |k, v|
        case k
          when :fw
            puts 'Firewall  ...  ok'

          when :shaper
            puts 'Shaper  ...  ok'
        end
      end
    end
  end
end
