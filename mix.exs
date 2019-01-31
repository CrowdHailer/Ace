defmodule Ace.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ace,
      version: "0.18.3",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_options: [
        # Will be done when switching to ssl handshake
        # warnings_as_errors: true
      ],
      description: description(),
      docs: [
        main: "readme",
        source_url: "https://github.com/crowdhailer/ace",
        extras: [
          "README.md"
        ]
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
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
      {:raxx, "~> 0.17.0"},
      {:excoveralls, "~> 0.8", only: :test},
      {:dialyxir, "~> 0.5.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false}
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
