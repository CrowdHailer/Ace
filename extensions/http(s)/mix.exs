defmodule Ace.HTTP.Mixfile do
  use Mix.Project

  def project do
    [app: :ace_http,
     version: "0.3.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     description: description(),
     docs: [extras: ["README.md"], main: "readme"],
     package: package()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:raxx, "~> 0.11.0"},
      {:http_status, "~> 0.2.0"},
      {:ace, "~> 0.9.0"},
      {:raxx_verify, "~> 0.1", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    HTTP Server built on top of Ace TCP connection manager
    """
  end

  defp package do
    [
     maintainers: ["Peter Saxton"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/CrowdHailer/Ace/tree/master/extensions/http(s)"}]
  end
end
