module NodeCtld::RemoteCommands
  class WatchdogStatus < Base
    handle :watchdog_status

    def exec
      {
        ret: :ok,
        output: {
          start_monotonic: @daemon.start_monotonic,
          last_transaction_check_monotonic: @daemon.last_transaction_check_monotonic
        }
      }
    end
  end
end
