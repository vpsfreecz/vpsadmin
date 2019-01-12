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
end
