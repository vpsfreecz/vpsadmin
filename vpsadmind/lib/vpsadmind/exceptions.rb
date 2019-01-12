module VpsAdmind
  class SystemCommandFailed < StandardError
    attr_reader :cmd, :rc, :output

    def initialize(cmd, rc, out)
      @cmd = cmd
      @rc = rc
      @output = out
    end

    def message
      "command '#{@cmd}' exited with code '#{@rc}', output: '#{@output}'"
    end
  end

  class CommandNotImplemented < StandardError

  end

  class CommandFailed < StandardError
    def initialize(error)
      super('command failed')
      @error = error
    end

    def error
      if @error.is_a?(String)
        {error: @error}
      else
        @error
      end
    end
  end
end
