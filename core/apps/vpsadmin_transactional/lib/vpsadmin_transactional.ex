defmodule VpsAdmin.Transactional do
  @moduledoc """
  Foundation for execution of cluster-wide transaction chains.

  This application handles execution of transaction chains in the cluster.
  Chains are executed using `VpsAdmin.Transactional.Chain.run/1`.

  This chain execution layer is not using `VpsAdmin.Persistence` at all,
  executed chains are independent on the persistence layer.
  `VpsAdmin.Persistence` and `VpsAdmin.Transactional` are combined by
  the `VpsAdmin.Cluster` application, but function independently.
  This is to ensure that vpsAdmin works even without the central database,
  on which `VpsAdmin.Persistence` relies.

  ## Inner workings
  New chain is distributed by `VpsAdmin.Transactional.Chain.Controller` to all
  nodes involved in the chain. Chain state is stored in the
  `VpsAdmin.Transactional.State` process. Chain execution is handled by
  `VpsAdmin.Transactional.Chain.Executor`, which in turn start
  `VpsAdmin.Transactional.Transaction.Executor` processes to execute
  transactions. Transactions execute commands via
  `VpsAdmin.Transactional.Queue`, which handles various queues and their sizes.

  Chain and transaction executors are using strategies to determine what
  transactions/commands should be executed or rolled back at which time.
  For now, there is only one strategy called
  `VpsAdmin.Transactional.Strategy.AllOrNone`, which executes transactions/
  commands one by one and starts rolling back on error.

  Chain and transaction executors can safely crash on errors and be restarted.
  On start, they fetch the current state from `VpsAdmin.Transactional.State`.
  On the other hand, when `VpsAdmin.Transactional.State` crashes, we cannot
  restart it, as the state was lost. This needs to be further worked on.
  """
end
