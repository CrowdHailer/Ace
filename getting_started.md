# Getting Started

Welcome to Ace.
This guide will walk through the key features of HTTP/2.0.
It will explain how Ace is built to take advantage of these features.

*Want to dive straight in? see `Ace.HTTP2.Service` or `Ace.HTTP2.Client`.*

## Connections and Streams
client setup

server setup

diagram

## Streaming

HTTP maps the request of a client to a server generated response.
This is true in HTTP/2.0, as it was in HTTP/1.x.

*In HTTP/2.0 a request/response pair form a single stream.*

In HTTP/2.0 the bodies of individual request's and response's are multiplexed in with other streams.
Ace provides an API that is equally able to handle processing requests/responses as stream, handling each fragment as it arrives, or as an atomic unit.

The `body` attribute of an `Ace.Request` or `Ace.Response` may be one of three types.

- `:false` - There IS NO body, for example `:GET` requests always have no body.
- `io_list()` - This body is complete encapsulated in this request/response.
- `:true` - There IS a body, it will be streamed as fragments it is received.

We can see all of these in action in a simple interaction

*NOTES:*

1. *Applications are not required to use `receive` directly; helpers are available for both client and server.*

```elixir
alias Ace.Request
alias Ace.Response
alias Ace.HTTP2.Client
alias Ace.HTTP2.Server

# ON CLIENT: prepare and send request.

# This will create a request where there is no body.
request = Request.get("/", [{"accept", "text/plain"}])
Client.send_request(client_stream, request)

# ON SERVER: respond to client

# Await a clients request
receive do
  {server_stream, %Request{method: :GET, path: "/", body: false}} ->
    # This response has been constructed with it's complete body and can be sent as a whole.
    response = Response.new(200, [{"content-type", "text/plain"}], "Hello, World!")
    Server.send_response(server_stream, response)
end

# ON CLIENT: The client receives each part of the request as it is streamed
receive do
  {client_stream, %Response{status: 200}} ->
    IO.inspect("Streaming response, ok.")
end
receive do
  {client_stream, %{data: data, end_stream: true}} ->
    IO.inspect("received data, '#{data}'")
end
```

## Server Push

###

### Stream handlers

The first step is define a stream handler for you application.
Using the Raxx adapter is the simplest way to get started.

```elixir
defmodule MyApp.SimpleHandler do
  use Ace.Raxx.Handler

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

    Ace.HTTP2.Service.start_link(
      {MyApp.SimpleHandler, :config},
      port: 8443,
      certfile: certfile,
      keyfile: keyfile,
      connections: 1_000
    )
  end
end
```

##### Note

`Ace.HTTP2.Service.start_link/2` Can be used to add one or more HTTP2 endpoint to an application supervision tree.
explain how Ace is good at OTP
