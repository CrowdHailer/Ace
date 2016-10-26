# Ace
**Ace server for managing TCP endpoints and connections.**

I tackled this project as an interesting Elixir exercise and to learn about TCP.
The code is designed to be accessible and is thoroughly commented.

For more details look at [Ace 0.1](https://github.com/CrowdHailer/Ace/tree/0.1.0).

If you are looking for a production webserver I would recommend one of:

- [elli](https://github.com/knutin/elli)
- [cowboy](https://ninenines.eu/docs/en/cowboy/1.0/guide/)/[ranch](https://ninenines.eu/docs/en/ranch/1.2/guide/)
- [mochiweb](https://github.com/mochi/mochiweb)

## Introduction

TCP endpoints are started with a pool of acceptors.
Servers are started on demand for each client connection.

*[Many servers one client, NOT many clients one server.](http://joearms.github.io/2016/03/13/Managing-two-million-webservers.html)*

Ace is responsible for managing server *processes*.
Server *modules* describe the communication patterns with clients.

[Documentation for Ace is available on hexdoc](https://hexdocs.pm/ace)

## Installation

[Available on Hex](https://hex.pm/packages/ace), the package can be installed as:

  1. Add `ace` to your list of dependencies in `mix.exs`:

        def deps do
          [{:ace, "~> 0.7.0"}]
        end

## Usage

Ace manages TCP connections by refering to a user defined server behaviour.
An Ace server must implement 4 callbacks:

- `init(connection, configuration)` for establishing a new connection.
- `handle_packet(packet, state)` to handle incomming TCP packets.
- `handle_info(message, state)` to handle application messages sent to the server.
- `terminate` to do any cleanup when the connection is closed.

#### Server

Example server.

```elixir
defmodule MyServer do
  def init(_connection, state = {:greeting, greeting}) do
    {:send, greeting, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end

  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end

  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end
```

Defining `MyServer` above we can use it to start an Ace endpoint.

#### Quick start

From the console, start mix.

```shell
iex -S mix
```

In the `iex` console, start a TCP endpoint.
```elixir
app = {MyServer, {:greeting, "WELCOME"}}
{:ok, pid} = Ace.TCP.start_link(app, port: 8080)
```

#### Embedded endpoints

It is not a good idea to start unsupervised processes.
For this reason an Ace endpoint can be added to you application supervision tree.

```elixir
children = [
  worker(Ace.TCP, [{MyServer, {:greeting, "WELCOME"}}, [port: 8080]])
]
Supervisor.start_link(children, opts)
```

See "01 Quote of the Day" for an example setup.

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

## The plan

1. To take this obviously deficient TCP echo server that I wrote as a beginner elixir developer and create a fully fledged HTTP server.
2. Keep reasonable notes of progress so others can learn about how to build a web server in elixir.
3. See what progress I have made in a year as an elixir developer.

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

## Resources I used to get this far

- https://github.com/tominated/elixir_http_server
- http://www.neo.com/2014/01/14/elixir-and-the-internet-of-things-handling-a-stampede
- https://erlangcentral.org/wiki/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles
