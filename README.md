# Ace

**HTTP web server and client, supports http1 and http2**

- [Install from Hex](https://hex.pm/packages/ace)
- [Documentation available on hexdoc](https://hexdocs.pm/ace)

## Features

- [x] Consistent server and client interfaces
- [x] Stream isolation; one process per stream
- [x] Bidirectional streaming; send and receive streamed data
- [x] Server push; to reduce latency
- [x] Automatic flow control; at stream and connection level
- [x] Secure data transport; TLS(SSL) support via ALPN
- [x] Verified against [h2spec](https://github.com/summerwind/h2spec) (*143/146*)
- [x] Simple request/response interactions; [Raxx](https://github.com/crowdhailer/raxx) interface
- [ ] HTTP upgrade mechanisms
- [ ] HTTP/1.1 pipelining

*View progress on the [roadmap](https://github.com/CrowdHailer/Ace/projects/1).*

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
