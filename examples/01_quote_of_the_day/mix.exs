defmodule QuoteOfTheDay.Mixfile do
  use Mix.Project

  def project do
    [app: :quote_of_the_day,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger],
     mod: {QuoteOfTheDay, []}]
  end

  defp deps do
    [
      {:ace, ">= 0.6.0", path: "../../"}
    ]
  end
end
