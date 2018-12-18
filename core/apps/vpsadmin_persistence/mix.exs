defmodule VpsAdmin.Persistence.MixProject do
  use Mix.Project

  def project do
    [
      app: :vpsadmin_persistence,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VpsAdmin.Persistence.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:mariaex, ">= 0.0.0"},
      {:ecto_enum, "~> 1.0"},
      {:jason, ">= 0.0.0"},
      {:yaml_elixir, ">= 0.0.0"}
    ]
  end
end
