defmodule HelloHTTP2.Mixfile do
  use Mix.Project

  def project do
    [app: :hello_http2,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger],
     mod: {HelloHTTP2.Application, []}]
  end

  defp deps do
    [
      {:ace, path: "../.."},
      {:raxx_static, "~> 0.6.1"},
      {:dialyxir, "~> 0.5.0", only: :dev},
    ]
  end
end
