The aim of this guide is to get you serving content as soon as possible.

### Prerequisits

This guide assumes Elixir [is already installed](https://elixir-lang.org/install.html).

### A new project

Start a new project using mix:

```
$ mix new hello --sup
$ cd hello
```

- The name of our project is `hello`, replace with your own.
- The `--sup` flag is used because our project will start processes, i.e. it is not just library code.

### Add Ace to project

Our newly created project includes a `mix.exs` file.
This file includes a list of dependencies, where we can add Ace.

```elixir
defp deps do
  [
    {:ace, "~> 0.14.6"}
  ]
end
```

To install all dependencies with mix run:

```
$ mix deps.get
```

### Start a Service

*Note and a `service` consists of many servers, one for each client. Starting a service can be considered the same as starting the 'server'.*

Our service needs to start when the application is started.
To start a service add it to the list of children found in `lib/hello/application.ex`.

```elixir
def start(_type, _args) do
  children = [
    {Ace.HTTP.Service, {Hello.WWW, %{}, [port: 8443]}}
  ]

  opts = [strategy: :one_for_one, name: Hello.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Now our application will run.
A mix projected is started by the command:

```
$ iex -S mix
```

Visit https://localhost:8443.

### Create a Homepage

`Hello.WWW` is the definition of our web application.
Let's create one that servers a single homepage

> use impl
