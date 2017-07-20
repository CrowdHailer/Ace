defmodule Ace.Mixfile do
  use Mix.Project

  def project do
    [app: :ace,
    version: "0.9.1",
    elixir: "~> 1.4",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps(),
    description: description(),
    docs: [extras: ["README.md"], main: "readme"],
    package: package()]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:hpack, "~> 1.0"},
      {:raxx, "~> 0.11.1", optional: true},
      # {:river, "~> 0.0.4"},
      {:dialyxir, "~> 0.5.0", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    Easy TCP and TLS(ssl) servers.

    For a HTTP webserver see https://hex.pm/packages/ace_http.
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
