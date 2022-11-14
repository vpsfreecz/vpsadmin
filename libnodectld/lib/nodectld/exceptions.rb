require 'libosctl'

module NodeCtld
  SystemCommandFailed = OsCtl::Lib::Exceptions::SystemCommandFailed

  class CommandNotImplemented < StandardError ; end
end
