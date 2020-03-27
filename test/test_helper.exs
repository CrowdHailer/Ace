Code.require_file("support.exs", __DIR__)

ExUnit.start()
ExUnit.configure(exclude: [ci: true])