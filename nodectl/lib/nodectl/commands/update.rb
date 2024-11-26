module NodeCtl
  class Commands::Update < Command::Remote
    cmd :update
    args '<command>'
    description 'Update information about VPS'

    def options(parser, _args)
      parser.separator <<~END

        Subcommands:
        ssh-host-keys [vps...]    Update SSH host keys
        os-release [vps...]       Update OS template info by reading /etc/os-release
      END
    end

    def validate
      if args.empty?
        raise ValidationError, 'missing subcommand'
      elsif !%w[ssh-host-keys os-release].include?(args[0])
        raise ValidationError, "invalid subcommand '#{args[0]}'"
      end

      params.update(
        command: args[0],
        vps_ids: args[1..].map(&:to_i).select { |v| v > 0 }
      )
    end

    def process
      puts 'Update in progress'
    end
  end
end
