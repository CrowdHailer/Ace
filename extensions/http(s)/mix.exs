defmodule Ace.HTTP.Mixfile do
  use Mix.Project

  def project do
    [app: :ace_http,
     version: "0.4.6",
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
      {:raxx, "~> 0.12.0"},
      {:http_status, "~> 0.2.0"},
      {:ace, "~> 0.9.2"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:httpoison, "~> 0.13.0"}
    ]
  end

  defp description do
    """
    HTTP and HTTPS webservers built with the Ace connection manager
    """
  end

  defp package do
    [
     maintainers: ["Peter Saxton"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/CrowdHailer/Ace/tree/master/extensions/http(s)"}]
  end
end
