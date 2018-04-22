module NodeCtl
  class CommandTemplates::ResourceControl < Command::Remote
    args 'all|fw|shaper'

    def validate
      if args.size < 1
        raise ValidationError, 'missing resource'

      elsif !%w(all fw shaper).include?(args[0])
        raise ValidationError, 'not a valid resource'
      end

      params.update({
        resources: args[0] == 'all' ? [:fw, :shaper] : [args[0]]
      })
    end

    def process
      response.each do |k, v|
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
