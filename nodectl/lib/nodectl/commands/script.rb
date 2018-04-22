module NodeCtl::Commands
  class Script < NodeCtl::Command
    args '<file>'
    description 'Run ruby script with libnodectld and nodectl in path'
    remote false

    def exec
      unless ARGV[1]
        raise NodeCtl::ValidationError, 'missing script name'
      end

      load(ARGV[1])
    end
  end
end
