defmodule VpsAdmin.Persistence.Mixfile do
  use Mix.Project

  def project do
    [
      app: :vpsadmin_persistence,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      aliases: aliases(),
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VpsAdmin.Persistence.Application, []},
    ]
  end

  defp deps do
    [
      {:ecto, "~> 2.2"},
      {:postgrex, "> 0.0.0"},
      {:ecto_enum, git: "https://github.com/gjaldon/ecto_enum"},
      {:poison, "> 0.0.0"},
      {:ex_machina, "> 0.0.0"},
    ]
  end

  defp aliases do
    [
      "test": ["ecto.create", "ecto.load", "test"],
    ]
  end
end
