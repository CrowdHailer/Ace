# Ace

**HTTP web server and client, supports http1 and http2**

[![Hex pm](http://img.shields.io/hexpm/v/ace.svg?style=flat)](https://hex.pm/packages/ace)
[![Build Status](https://secure.travis-ci.org/CrowdHailer/Ace.svg?branch=master
"Build Status")](https://travis-ci.org/CrowdHailer/Ace)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

- [Install from Hex](https://hex.pm/packages/ace)
- [Documentation available on hexdoc](https://hexdocs.pm/ace)
- [Discuss on slack](https://elixir-lang.slack.com/messages/C56H3TBH8/)

See [Raxx.Kit](https://github.com/CrowdHailer/raxx_kit) for a project generator that helps you set up
a web project based on [Raxx](https://github.com/CrowdHailer/raxx)/[Ace](https://github.com/CrowdHailer/Ace).

## Get started

#### Hello, World!
```elixir
defmodule MyApp do
  use Ace.HTTP.Service, [port: 8080, cleartext: true]
  use Raxx.SimpleServer

  @impl Raxx.SimpleServer
  def handle_request(%{method: :GET, path: []}, %{greeting: greeting}) do
    response(:ok)
    |> set_header("content-type", "text/plain")
    |> set_body("#{greeting}, World!")
  end
end
```

*The arguments given to use Ace.HTTP.Service are default values when starting the service.*

#### Start the service

```elixir
config = %{greeting: "Hello"}

MyApp.start_link(config, [port: 1234])
```

*Here the default port value has been overridden at startup*

#### Raxx

Ace implements the Raxx HTTP interface.
This allows applications to be built with any components from the Raxx ecosystem.

Raxx has tooling for streaming, server-push, routing, api documentation and more. See [documentation](https://hexdocs.pm/raxx/readme.html) for details.

*The correct version of raxx is included with ace, raxx does not need to be added as a dependency.*

#### TLS/SSL

If a service is started without the `cleartext` it will start using TLS. This requires a certificate and key.

```elixir
config = %{greeting: "Hello"}
options = [port: 8443, certfile: "path/to/certificate", keyfile: "path/to/key"]

MyApp.start_link(application, options)
```

*TLS is required to serve content via HTTP/2.*

#### Supervising services

The normal way to run services is as part of a projects supervision tree. When starting a new project use the `--sup` flag.

```sh
mix new my_app --sup
```

Add the services to be supervised in the application file `lib/my_app/application.ex`.

```elixir
defmodule MyApp.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {MyApp, [%{greeting: "Hello"}]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Start project using `iex -S mix` and visit [http://localhost:8080](http://localhost:8080).

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
