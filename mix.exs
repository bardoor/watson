defmodule Watson.MixProject do
  use Mix.Project

  def project do
    [
      app: :watson,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Watson.CLI],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: ~w(kernel stdlib logger)a,
      mod: {Watson.Application, []}
    ]
  end

  defp deps do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
