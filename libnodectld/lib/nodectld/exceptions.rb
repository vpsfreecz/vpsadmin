require 'libosctl'

module NodeCtld
  SystemCommandFailed = OsCtl::Lib::Exceptions::SystemCommandFailed

  class CommandNotImplemented < StandardError ; end

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
