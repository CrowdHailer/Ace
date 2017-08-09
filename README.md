# Ace

**HTTP/2 server and client for Elixir**

- [Install from Hex](https://hex.pm/packages/ace)
- [Documentation available on hexdoc](https://hexdocs.pm/ace)

## Features

- Consistent server and client interfaces
- Stream isolation; one process per stream
- Bidirectional streaming; send and receive streamed data
- Secure data transport; TLS(SSL) support via ALPN
- Verified against [h2spec](https://github.com/summerwind/h2spec) (*143/146*)
- Simple request/response interactions; [Raxx](https://github.com/crowdhailer/raxx) interface

*For more view the [features board](https://github.com/CrowdHailer/Ace/projects/1).*

## Guides

- **[Getting started](getting_started.md)**

*For TCP/TLS server see [previous version](https://github.com/CrowdHailer/Ace/tree/0.9.x).*

## Testing

Run [h2spec](https://github.com/summerwind/h2spec) against the example `hello_http2` application.

1. Start the example app.
  ```
  cd examples/hello_http2
  iex -S mix
  ```
2. Run h2spec from docker
  ```
  sudo docker run --net="host" summerwind/h2spec --port 8443 -t -k -S
  ```
