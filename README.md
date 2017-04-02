# Ace
**Easy TCP and TLS(ssl) servers.**

- [Install from hex](https://hex.pm/packages/ace)
- [Documentation on hexdoc](https://hexdocs.pm/ace)

*For a HTTP webserver see [Ace.HTTP](https://hex.pm/packages/ace_http).*

## Application

An `Ace.Application` module defines a servers behaviour.


```elixir
defmodule MyApp do
  # MyApp is a server application.
  use Ace.Application

  # Handle client opening a new connection.
  def handle_connect(_connection, state = {:greeting, greeting}) do
    {:send, greeting, state}
  end

  # React to a message that was sent from the client.
  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\n", state}
  end

  # React to a message recieved from the application.
  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\n", state}
  end

  # Response to the client closing the connection.
  def handle_disconnect(_reason, _state) do
    IO.puts("Socket connection closed")
  end

  # Define start_link to `MyApp` can be added to supervision tree.
  def start_link(greeting, options \\ []) do
    config = {:greeting, greeting}
    app = {__MODULE__, config}
    Ace.TCP.start_link(app, options)
  end
end
```

#### Quick start

From the console, start mix.

```shell
iex -S mix
```

In the `iex` console, start a TCP endpoint.
```elixir
{:ok, pid} = MyApp.start_link("WELCOME", port: 8080)
```

#### Connect
Use telnet to communicate with the server.

```
telnet localhost 8080
```

Wihin the telnet terminal.

```
# once connected
WELCOME
hi
ECHO: hi
```

In the iex session.

```
send(server, {:notify, "BOO!"})
```

back in telnet terminal.

```
BOO!
```

#### Embedded endpoints

It is not a good idea to start unsupervised processes.
Ace endpoints should be added to you application supervision tree.

```elixir
@tcp_options [
  port: 8080
]

@tls_options [
  port: 8443,
  certificate: "path/to/cert.pm",
  certificate_key: "path/to/key.pm"
]

children = [
  worker(Ace.TCP, [{MyApp, {:greeting, "WELCOME"}}, @tcp_options])
  worker(Ace.TLS, [{MyApp, {:greeting, "WELCOME"}}, @tls_options])
]
Supervisor.start_link(children, opts)
```

See "01 Quote of the Day" for an example setup.

### Ace 0.1 (TCP echo)

The simplest TCP echo server that works.
Checkout the source of [version 0.1.0](https://github.com/CrowdHailer/Ace/blob/0.1.0/server.ex).
The [change log](https://github.com/CrowdHailer/Ace/blob/master/CHANGELOG.md) documents all enhancements to this prototype server.


## Using Vagrant

Vagrant manages virtual machine provisioning.
Using Vagrant allows you to quickly get started with `Ace` without needing to install Elixir/erlang on you machine.

*If you do not know vagrant, or have it on your machine, I would suggest just installing Elixir on your machine and ignoring this section.*

```
vagrant up

vagrant ssh

cd /vagrant
```

From this directory instructions will be that same as users running Elixir on their machine.

## Contributing

Before opening a pull request, please open an issue first.

Once we've decided how to move forward with a pull request:

    $ git clone git@github.com:CrowdHailer/Ace.git
    $ cd Ace
    $ mix deps.get
    $ mix test
    $ mix dialyzer.plt
    $ mix dialyzer

Once you've made your additions, `mix test` passes and `mix dialyzer` reports no warnings, go ahead and open a PR!
