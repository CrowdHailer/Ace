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

The `body` attribute of an `Raxx.Request` or `Raxx.Response` may be one of three types.

- `:false` - There IS NO body, for example `:GET` requests always have no body.
- `io_list()` - This body is complete encapsulated in this request/response.
- `:true` - There IS a body, it will be streamed as fragments it is received.

We can see all of these in action in a simple interaction

*NOTES:*

1. *Applications are not required to use `receive` directly; helpers are available for both client and server.*

```elixir
alias Ace.HTTP2.Client
alias Ace.HTTP2.Server

# ON CLIENT: prepare and send request.

# This will create a request where there is no body.
request = Raxx.request(:GET, "/")
|> Raxx.set_header("accept", "text/plain")
Ace.HTTP2.send(client_stream, request)

# ON SERVER: respond to client

# Await a clients request
receive do
  {server_stream, %Request{method: :GET, path: "/", body: false}} ->
    # This response has been constructed with it's complete body and can be sent as a whole.
    response = Raxx.response(200, [{"content-type", "text/plain"}], "Hello, World!")
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

TODO

### TLS(SSL) credentials

Ace only supports using a secure transport layer.
Therefore a certificate and certificate_key are needed to server content.

For local development a [self signed certificate](http://how2ssl.com/articles/openssl_commands_and_tips/) can be used.

##### Note

Store certificates in a projects `priv` directory if they are to be distributed as part of a release.
