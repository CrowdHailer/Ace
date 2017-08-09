# Getting Started

*These instructions are for setting up a server, see `Ace.HTTP2.Client` for working with the HTTP/2.0 client.*

Welcome to Ace;
Once added to your project this guide will demonstrate setting up a simple end point.

### Stream handlers

The first step is define a stream handler for you application.
Using the Raxx adapter is the simplest way to get started.

```elixir
defmodule MyApp.SimpleHandler do
  use Ace.HTTP2.Stream.RaxxHandler

  def handle_request(_request, _config) do
    Raxx.Response.ok("Hello, World!", [{"content-length", "13"}])
  end
end
```

A stream handler and configuration are used to start a worker for every stream.

##### Note

The Raxx handler is provided when simple request -> response usecases.
Defining a custom handler can support streaming up or down (or both).

### TLS(SSL) credentials

Ace only supports using a secure transport layer.
Therefore a certificate and certificate_key are needed to server content.

For local development a [self signed certificate](http://how2ssl.com/articles/openssl_commands_and_tips/) can be used.

##### Note

Store certificates in a projects `priv` directory if they are to be distributed as part of a release.

### Endpoint setup

```elixir
defmodule MyApp.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do

    certfile = Application.app_dir(:my_app, "/priv/cert.pem")
    keyfile = Application.app_dir(:my_app, "/priv/key.pem")

    Ace.HTTP2.start_link(
      {MyApp.SimpleHandler, :config},
      8443,
      certfile: certfile,
      keyfile: keyfile,
      connections: 1_000
    )
  end
end
```

##### Note

`Ace.HTTP2.start_link/3` Can be used to add one or more HTTP2 endpoint to an application supervision tree.

## Bidirectional streaming

Process will receive data messages in the following format untill
all data is sent from client

*1*
`{stream, %{headers: list(), end_stream: boolean()}}`

*0 - n*
`{stream, %{data: binary(), end_stream: boolean()}}`

The worker can stream data to the client at any point using
```elixir
Server.send(stream, %{headers: headers(),  end_stream: boolean()})
# OR
Server.send(stream, %{data: binary(), end_stream: boolean()})
```

#### Example

```elixir
defmodule MyApp.StreamHandler do
  use GenServer
  alias Ace.HTTP2.StreamHandler

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def handle_info({stream, {:headers, _}}, state) do
    response_headers = %{
      headers: [{":status", "200"}, {"content-length", "13"}],
      end_stream: false
    }
    Server.send(stream, response_headers)
    response_body = %{
      data: "Hello, World!",
      end_stream: true
    }
    Server.send(stream, response_body)
    {:stop, :normal, state}
  end
end
```
