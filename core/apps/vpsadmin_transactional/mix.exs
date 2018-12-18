defmodule VpsAdmin.Transactional.MixProject do
  use Mix.Project

  def project do
    [
      app: :vpsadmin_transactional,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VpsAdmin.Transactional.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, ">= 0.0.0"},
      {:vpsadmin_base, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
