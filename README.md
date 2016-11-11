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

The package is available on [Hex](https://hex.pm/packages/ace).
Ace can be installed by adding it to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ace, "~> 0.7.0"}]
end
```

## Usage

#### Server

Define the server that will be used to start an Ace endpoint.

```elixir
defmodule MyServer do
  # Initialise a server for a new client.
  def init(_connection, state = {:greeting, greeting}) do
    {:send, greeting, state}
  end

  # React to a message that was sent from the client.
  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end

  # React to a message recieved from the application.
  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end

  # Response to the client closing the connection.
  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
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
