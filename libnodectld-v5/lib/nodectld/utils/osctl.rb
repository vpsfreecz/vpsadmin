require 'json'

module NodeCtld
  module Utils::OsCtl
    # @param cmd [Symbol, Array<Symbol>] command name(s)
    # @param args [Array] command arguments
    # @param opts [Hash] command options
    # @param gopts [Hash] global command options
    # @param cmd_opts [Hash] options passed to {Utils::System#syscmd}
    # @return [OsCtl::Lib::SystemCommandResult]
    def osctl(cmd, args = [], opts = {}, gopts = {}, cmd_opts = {})
      argv = ['osctl']

      # Global options
      argv.concat(format_cli_options(gopts))
      argv << '-j'

      # Command
      if cmd.is_a?(Array)
        argv.concat(cmd)
      else
        argv << cmd
      end

      # Options
      argv.concat(format_cli_options(opts))

      # Arguments
      if args.is_a?(Array)
        argv.concat(args)
      else
        argv << args
      end

      syscmd(argv.join(' '), cmd_opts)
    end

    # Shortcut for {#osctl} with global option `pool`
    # @param pool [String] pool name
    # @param cmd [Symbol, Array<Symbol>] command name(s)
    # @param args [Array] command arguments
    # @param opts [Hash] command options
    # @param gopts [Hash] global command options
    # @param cmd_opts [Hash] options passed to {Utils::System#syscmd}
    # @return [OsCtl::Lib::SystemCommandResult]
    def osctl_pool(pool, cmd, args = [], opts = {}, gopts = {}, cmd_opts = {})
      osctl(cmd, args, opts, gopts.merge({ pool: }), cmd_opts)
    end

    def osctl_parse(*)
      JSON.parse(osctl(*).output, symbolize_names: true)
    end

    def format_cli_options(opts)
      ret = []

      opts.each do |k, v|
        if v === true
          ret << "--#{k.to_s.gsub('_', '-')}"

        elsif v === false
          ret << "--no-#{k.to_s.gsub('_', '-')}"

        elsif v.is_a?(Array)
          v.each do |arg|
            ret << "--#{k.to_s.gsub('_', '-')}" << "\"#{arg}\""
          end

        else
          ret << "--#{k.to_s.gsub('_', '-')}" << "\"#{v}\""
        end
      end

      ret
    end
  end
end
