module NodeCtl
  class Commands::Queue < Command::Remote
    cmd :queue
    args '<queue> <command> [args...]'
    description 'Manage execution queues'

    def options(parser, args)
      parser.separator <<END
Subcommands:
pause [SECONDS]          List transaction confirmations
resume                   Run transaction confirmations
END

    end

    def validate
      if !%w(pause resume resize).include?(args[0])
        raise ValidationError, 'unknown command: expected pause or resume'
      elsif args.size < 2
        raise ValidationError, 'arguments missing'
      end

      params.update({
        command: args[0],
        queue: args[1],
      })

      if args[0] == 'pause' && args[2]
        secs = args[2].to_i
        params[:duration] = secs if secs > 0
      elsif args[0] == 'resize'
        size = args[2].to_i
        raise ValidationError, 'invalid queue size' if size <= 0

        params[:size] = size
      end
    end
  end
end
