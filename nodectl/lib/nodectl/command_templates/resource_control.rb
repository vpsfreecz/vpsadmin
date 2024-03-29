module NodeCtl
  class CommandTemplates::ResourceControl < Command::Remote
    args 'all|shaper'

    def validate
      if args.empty?
        raise ValidationError, 'missing resource'

      elsif !%w[all shaper].include?(args[0])
        raise ValidationError, 'not a valid resource'
      end

      params.update({
                      resources: args[0] == 'all' ? [:shaper] : [args[0]]
                    })
    end

    def process
      response.each_key do |k|
        case k
        when :shaper
          puts 'Shaper  ...  ok'
        end
      end

      ok
    end
  end
end
