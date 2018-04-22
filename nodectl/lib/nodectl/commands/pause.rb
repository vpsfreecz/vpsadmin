module NodeCtl
  class Commands::Pause < Command::Remote
    cmd :pause
    args '[ID]'
    description 'Pause execution of queued transactions'

    def validate
      if args.size > 1
        raise ValidationError, 'too many arguments'

      elsif specific?
        raise ValidationError, 'invalid transaction id' if args[0] !~ /^\d+$/
      end

      params[:t_id] = specific? ? args[0].to_i : nil
    end

    def process
      if specific?
        puts 'Pause scheduled'

      else
        puts 'Paused'
      end
    end

    def specific?
      args.size == 1
    end
  end
end
