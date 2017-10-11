defmodule VpsAdmin.Cluster.Mixfile do
  use Mix.Project

  def project do
    [app: :vpsadmin_cluster,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.5",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     aliases: aliases()]
  end

  def application do
    [extra_applications: [:logger],
     mod: {VpsAdmin.Cluster.Application, []}]
  end

  defp deps do
    [{:ecto, "~> 2.1"},
     {:postgrex, "> 0.0.0"},
     {:ecto_enum, "~> 1.0"},
     {:poison, "> 0.0.0"}]
  end

  defp aliases do
    ["test": ["ecto.create", "ecto.load", "test"]]
  end
end
