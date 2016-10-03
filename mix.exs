defmodule Ace.Mixfile do
  use Mix.Project

  def project do
    [app: :ace,
    version: "0.2.0",
    elixir: "~> 1.0",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps,
    description: description,
    docs: [extras: ["README.md"], main: "readme"],
    package: package]
  end

  def application do
    [
      applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    An Elixir webserver.
    """
  end

  defp package do
    [
      maintainers: ["Peter Saxton"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/crowdhailer/ace"}
    ]
  end
end
