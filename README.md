# Ace
### An educational Webserver for Elixir.

## The plan.

1. To take this obviously deficient TCP echo server that I wrote as a beginner elixir developer and create a fully fledged HTTP server.
2. Keep reasonable notes of progress so others can learn about how to build a web server in elixir.
3. See what progress I have made in a year as an elixir developer.

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
