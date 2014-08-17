module CommandTemplates
  class ResourceControl < Command
    args 'all|fw|shaper'

    def validate
      raise ValidationError.new('missing resource') if @args.size < 2
      raise ValidationError.new('not a valid resource') unless %w(all fw shaper).include?(@args[1])

      {resources: @args[1] == 'all' ? %i(fw shaper) : [@args[1]]}
    end

    def process
      @res.each do |k, v|
        case k
          when :fw
            if v.nil? || v.empty?
              puts 'Firewall  ...  ok'
            else
              puts 'Firewall'
              v.each do |k, v|
                puts "\t#{v} rules for IPv#{k}"
              end
            end

          when :shaper
            puts 'Shaper  ...  ok'
        end
      end

    end
  end
end
