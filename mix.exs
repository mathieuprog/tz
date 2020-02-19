defmodule Tz.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :tz,
      elixir: "~> 1.9",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      version: @version,
      package: package(),
      description: "Time zone support for Elixir",

      # ExDoc
      name: "Tz",
      source_url: "https://github.com/mathieuprog/tz",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache 2.0"],
      maintainers: ["Mathieu Decaffmeyer"],
      links: %{"GitHub" => "https://github.com/mathieuprog/tz"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
