defmodule VpsAdmin.Persistence.Query.Node do
  use VpsAdmin.Persistence.Query

  def preload do
    from(
      n in schema(),
      join: l in assoc(n, :location),
      join: e in assoc(l, :environment),
      select_merge: %{
        domain_name: fragment("CONCAT(?, '.', ?)", n.name, l.domain),
        fqdn: fragment("CONCAT(?, '.', ?, '.', ?)", n.name, l.domain, e.domain)
      }
    )
  end

  def list do
    from(
      n in preload(),
      order_by: [asc: n.id]
    )
    |> repo().all()
  end
end
