defmodule VpsAdmin.Transactional.Manager.Transaction do
  alias VpsAdmin.Transactional.Manager

  def abort(id), do: Manager.Transaction.Server.abort(id)
end
