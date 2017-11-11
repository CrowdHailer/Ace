defmodule Ace.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ace,
      version: "0.15.4",
      elixir: "~> 1.5",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      docs: [
        main: "readme",
        source_url: "https://github.com/crowdhailer/ace",
        extras: [
          "README.md"
        ]
      ],
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:hpack, "~> 0.2.3", hex: :hpack_erl},
      {:raxx, "~> 0.14.1"},
      {:dialyxir, "~> 0.5.0", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    HTTP web server and client, supports http1 and http2
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
