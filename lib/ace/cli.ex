# https://elixirforum.com/t/create-a-mix-archive-with-library-dependencies/9067/9
# Summary should probably not be in mix.
# should be an escript, looks like can be installed from hex

# This is also interesting
# https://github.com/ericentin/serve_this
defmodule Ace.Cli do
  @doc """
  Run a simple server file.

  For example given the follow `server.exs`.

      use Raxx.SimpleServer

      def handle_request(_request, _config) do
        response(:ok)
        |> set_body("Hello, world!")
      end

  Run the server by installing the Ace escript and running the file.
  """
  def main(opts) do
    case OptionParser.parse_head!(opts, strict: [port: :integer, config: :binary]) do
      {options, [file | argv]} ->
        server_code = File.read!(file)
        module_code = "defmodule Ace.Runnable do " <> server_code <> " end"
        System.argv(argv)

        {{:module, Ace.Runnable, _bytes, _return}, []} =
          Code.eval_string(module_code, [], file: file)

        config = Keyword.get(options, :config, nil)
        port = Keyword.get(options, :port, nil)

        {:ok, _pid} =
          Ace.HTTP.Service.start_link({Ace.Runnable, config}, port: port, cleartext: true)

        Process.sleep(:infinity)
    end
  end
end
