# https://elixirforum.com/t/create-a-mix-archive-with-library-dependencies/9067/9
# Summary should probably not be in mix.
# should be an escript, looks like can be installed from hex

# This is also interesting
# https://github.com/ericentin/serve_this
defmodule Ace.Cli do
  def main([file]) do
    # pass remaining options to file
    # https://hexdocs.pm/mix/master/Mix.Tasks.Escript.Install.html
    Application.ensure_all_started(:ace)
    |> IO.inspect()

    # Returns list of modules, but will also start a server if that code is there
    # I think we should do eval_file.
    # It might also be nice to read file wrap in a server module then eval. Ace.Runnable
    # Top level handle_request
    # Could go to a DSL but not necessary
    # take port options ace --port 8080 server.exs
    Code.require_file(file)
    |> IO.inspect()

    Process.sleep(:infinity)
  end
end
