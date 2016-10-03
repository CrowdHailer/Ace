# Ace
### An educational Webserver for Elixir.

# Hi

> If you are hear send me a message twitter/gh-issue, they're all good.
> I want to take a deep dive into TCP/HTTP and network protocols in general, so if your curious or on a similar voyage of discovery say hi.

> Cheers

## Installation

[Available on Hex](https://hex.pm/packages/ace), the package can be installed as:

  1. Add `ace` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:ace, "~> 0.2.0"}]
    end
    ```

## Usage

#### startup

From the console, start mix.

```shell
iex -S mix
```

In the `iex` console, start a TCP server.
```elixir
Ace.TCP.start(8080)
```

#### Connect
Use telnet to communicate with the echo server.

```
telnet localhost 8080

hi
ECHO: hi
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

*If you do not know vagrant on you machine I would suggest just installing elixir on your host machine and ignoring the instructions here.*

```
vagrant up

vagrant ssh

cd /vagrant
```

From this directory instructions will be that same as users running Elixir on their machine.

## Resources I used to get this far

- https://github.com/adamgamble/elixir_http_server
- https://github.com/tominated/elixir_http_server
- https://github.com/parroty/http_server
- http://www.neo.com/2014/01/14/elixir-and-the-internet-of-things-handling-a-stampede
