require 'libosctl'

module NodeCtld
  SystemCommandFailed = OsCtl::Lib::Exceptions::SystemCommandFailed

  class CommandNotImplemented < StandardError ; end

  class TransactionCheckError < StandardError ; end
end
