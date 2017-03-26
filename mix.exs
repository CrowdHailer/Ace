defmodule Ace.Mixfile do
  use Mix.Project

  def project do
    [app: :ace,
    version: "0.8.0",
    elixir: "~> 1.0",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps(),
    description: description(),
    docs: [extras: ["README.md"], main: "readme"],
    package: package()]
  end

  def application do
    [
      applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 0.5.0", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    Serve internet applications from TCP or TLS(ssl) endpoints.
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
