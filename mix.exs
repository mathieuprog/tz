defmodule Tz.MixProject do
  use Mix.Project

  @version "0.26.4"

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
      {:castore, "~> 0.1 or ~> 1.0", optional: true},
      {:mint, "~> 1.5", optional: true},
      {:ex_doc, "~> 0.29", only: :dev},
      {:benchee, "~> 1.1", only: :dev}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Mathieu Decaffmeyer"],
      links: %{
        "GitHub" => "https://github.com/mathieuprog/tz",
        "Sponsor" => "https://github.com/sponsors/mathieuprog"
      }
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
