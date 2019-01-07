defmodule VpsAdmin.Transactional.ManagerTest do
  use ExUnit.Case

  alias VpsAdmin.Base.Monitor
  alias VpsAdmin.Transactional.Command
  alias VpsAdmin.Transactional.Transaction
  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Transactional.Worker

  defmodule TestManager do
    use Manager

    def open_transactions do
      []
    end

    def get_transaction(id) do
      Transaction.new(id, :executing)
    end

    def get_commands(_id) do
      for x <- 1..10 do
        %Command{
          id: x,
          node: node(),
          queue: :default,
          reversible: :reversible,
          state: :queued,
          input: %{}
        }
      end
    end

    def close_transaction(t) do
      Monitor.publish(TestMonitor, {:transaction, :close}, t)
    end

    def abort_transaction(t) do
      Monitor.publish(TestMonitor, {:transaction, :abort}, t)
    end

    def command_started(t, c) do
      Monitor.publish(TestMonitor, {:command, :started}, {t, c})
    end

    def command_finished(t, c) do
      Monitor.publish(TestMonitor, {:command, :finished}, {t, c})
    end
  end

  defmodule SuccessfulWorker do
    use Worker

    def run_command({t, cmd}, func) do
      Manager.Transaction.Server.report_result({t, %{cmd | status: :done}})
    end
  end

  test "successful command execution" do
    Monitor.start_link(name: TestMonitor)
    start_supervised!({Manager.Supervisor, {TestManager, SuccessfulWorker}})

    :ok = Monitor.subscribe(TestMonitor, {:transaction, :close})
    :ok = Monitor.subscribe(TestMonitor, {:command, :finished})

    Manager.add_transaction(1, TestManager, SuccessfulWorker)

    for x <- 1..10 do
      assert {
               {:command, :finished},
               {
                 %Transaction{id: 1, state: :executing},
                 %Command{id: ^x, state: :executed, status: :done}
               }
             } = Monitor.read_one(TestMonitor)
    end

    assert {
             {:transaction, :close},
             %Transaction{id: 1, state: :done}
           } = Monitor.read_one(TestMonitor)
  end

  defmodule RollbackWorker do
    use Worker

    def run_command({t, %{id: 8, state: :executed} = cmd}, func) do
      Manager.Transaction.Server.report_result({t, %{cmd | status: :failed}})
    end

    def run_command({t, %{id: 8, state: :rolledback} = cmd}, func) do
      Manager.Transaction.Server.report_result({t, %{cmd | status: :done}})
    end

    def run_command({t, cmd}, func) do
      Manager.Transaction.Server.report_result({t, %{cmd | status: :done}})
    end
  end

  test "rollback command execution" do
    Monitor.start_link(name: TestMonitor)
    start_supervised!({Manager.Supervisor, {TestManager, RollbackWorker}})

    :ok = Monitor.subscribe(TestMonitor, {:transaction, :close})
    :ok = Monitor.subscribe(TestMonitor, {:command, :finished})

    Manager.add_transaction(1, TestManager, RollbackWorker)

    # Execution
    for x <- 1..7 do
      assert {
               {:command, :finished},
               {
                 %Transaction{id: 1, state: :executing},
                 %Command{id: ^x, state: :executed, status: :done}
               }
             } = Monitor.read_one(TestMonitor)
    end

    # Failure
    assert {
             {:command, :finished},
             {
               %Transaction{id: 1, state: :executing},
               %Command{id: 8, state: :executed, status: :failed}
             }
           } = Monitor.read_one(TestMonitor)

    # Rollback
    for x <- 8..1 do
      assert {
               {:command, :finished},
               {
                 %Transaction{id: 1, state: :rollingback},
                 %Command{id: ^x, state: :rolledback, status: :done}
               }
             } = Monitor.read_one(TestMonitor)
    end

    # Closure
    assert {
             {:transaction, :close},
             %Transaction{id: 1, state: :failed}
           } = Monitor.read_one(TestMonitor)
  end

  defmodule TransactionState do
    def start_link do
      Agent.start_link(
        fn ->
          %{
            transaction: Transaction.new(1, :executing),
            commands:
              for x <- 1..10 do
                %Command{
                  id: x,
                  node: node(),
                  queue: :default,
                  reversible: :reversible,
                  state: :queued,
                  input: %{}
                }
              end
          }
        end,
        name: __MODULE__
      )
    end

    def transaction do
      Agent.get(__MODULE__, fn %{transaction: t} -> t end)
    end

    def commands do
      Agent.get(__MODULE__, fn %{commands: cmds} -> cmds end)
    end

    def command_finished(t, c) do
      Agent.get_and_update(__MODULE__, fn %{transaction: t, commands: cmds} = state ->
        new_cmds =
          Enum.map(cmds, fn
            %{id: ^c.id} = cmd ->
              c

            cmd ->
              c
          end)

        {nil, %{state | transaction: t, cmds: new_cmds}}
      end)
    end

    def crash_once do
      do_crash =
        Agent.get_and_update(__MODULE__, fn
          %{crashed: true} = state ->
            {false, state}

          state ->
            {true, Map.put(state, :crashed, true)}
        end)

      if do_crash, do: raise("oops", else: nil)
    end
  end

  defmodule StateManager do
    use Manager

    def open_transactions do
      []
    end

    def get_transaction(id) do
      TransactionState.transaction()
    end

    def get_commands(_id) do
      TransactionState.commands()
    end

    def close_transaction(t) do
      Monitor.publish(TestMonitor, {:transaction, :close}, t)
    end

    def abort_transaction(t) do
      Monitor.publish(TestMonitor, {:transaction, :abort}, t)
    end

    def command_started(t, c) do
      Monitor.publish(TestMonitor, {:command, :started}, {t, c})
    end

    def command_finished(t, %{id: 5} = c) do
      TransactionState.crash_once()
      TransactionState.command_finished(t, c)
      Monitor.publish(TestMonitor, {:command, :finished}, {t, c})
    end

    def command_finished(t, c) do
      TransactionState.command_finished(t, c)
      Monitor.publish(TestMonitor, {:command, :finished}, {t, c})
    end
  end

  defmodule SuccessfulWorker do
    use Worker

    def run_command({t, cmd}, func) do
      Manager.Transaction.Server.report_result({t, %{cmd | status: :done}})
    end
  end

  test "execution state is remembered" do
  end
end
