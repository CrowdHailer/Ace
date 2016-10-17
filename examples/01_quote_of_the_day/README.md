# QuoteOfTheDay

**Quote of the day service simply sends a short message without regard
to the input.**

Implements [RFC 865](https://tools.ietf.org/html/rfc865).

The service starts on port 17. To use port 17 usually requires sudo access. If access to port 17 is not available to the user the application will fail to start with the error `{:error, :eacces}`.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `quote_of_the_day` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:quote_of_the_day, "~> 0.1.0"}]
    end
    ```

  2. Ensure `quote_of_the_day` is started before your application:

    ```elixir
    def application do
      [applications: [:quote_of_the_day]]
    end
    ```
