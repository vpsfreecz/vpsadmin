module NodeCtld::RemoteCommands
  class WatchdogDebug < Base
    handle :watchdog_debug

    def exec
      thread = @daemon.transaction_thread

      {
        ret: :ok,
        output: {
          last_transaction_check_monotonic: @daemon.last_transaction_check_monotonic,
          transaction_thread: {
            status: thread&.status,
            backtrace: thread&.backtrace || []
          }
        }
      }
    end
  end
end
