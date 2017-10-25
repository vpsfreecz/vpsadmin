defmodule VpsAdmin.Persistence.Factory do
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  use ExMachina.Ecto, repo: Persistence.Repo

  def location_factory do
    %Schema.Location{
      label: sequence(:label, &"Location ##{&1}"),
      domain: sequence(:domain, &"org#{&1}"),
      row_state: :confirmed,
    }
  end

  def node_factory do
    %Schema.Node{
      name: sequence(:node, &"node#{&1}"),
      ip_addr: "1.2.3.4",
      location: build(:location),
      row_state: :confirmed,
    }
  end
end
