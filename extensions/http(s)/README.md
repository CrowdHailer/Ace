# Ace.HTTP

**HTTP and HTTPS webservers built with the Ace connection manager.**

- [Install from Hex](https://hex.pm/packages/ace_http)
- [Documentation available on hexdoc](https://hexdocs.pm/ace_http)

## Raxx interface

`Ace.HTTP` and `Ace.HTTPS` will serve [Raxx](https://hexdocs.pm/raxx) applications.
For instruction on developing applications see the Raxx documentation:

- https://hexdocs.pm/raxx

## Chunked Responses

`Ace.ChunkedResponse` is an extension to the Raxx interface that allows a server to push data over a connection.

## Request errors

When a the data sent over a socket cannot be cast to a request in time then the applications `handle_error/1` callback will be invoked.

## Development

### Requirements

Running `Ace.HTTP` requires Elixir 1.4 or higher.

### Source code

Development is as part of the Ace project,
all code is available on Github.

- https://github.com/CrowdHailer/Ace

### Contributions

1. Fork it (https://github.com/crowdhailer/ace/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Run all [tests](#testing)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

### Testing

The included tests can be run from mix.

```
mix deps.get
mix test
```
