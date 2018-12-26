defmodule VpsAdmin.Transactional.Worker do
  alias VpsAdmin.Transactional.Command
  alias VpsAdmin.Transactional.Transaction

  @callback run_command(
              {Transaction.id(), Command.t()},
              :execute | :rollback
            ) :: {:ok, pid}

  defmacro __using__(_opts) do
    quote do
      @behaviour VpsAdmin.Transactional.Worker
      alias VpsAdmin.Transactional
    end
  end
end
