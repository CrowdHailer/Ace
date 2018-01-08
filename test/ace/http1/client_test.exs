defmodule Ace.HTTP1.ClientTest do
  use ExUnit.Case, async: true

  # REQUEST

  test "sends the correct method" do
    request = Raxx.request(:GET, "/anything")
    request = %{request | authority: "httpbin.org"}
    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")

    assert String.contains?(response.body, "\"method\": \"GET\"")

    request = Raxx.request(:DELETE, "/anything")
    request = %{request | authority: "httpbin.org"}
    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")

    assert String.contains?(response.body, "\"method\": \"DELETE\"")
  end

  test "sends correct host header from request" do
    request = Raxx.request(:GET, "/headers")
    request = %{request | authority: "httpbin.org"}

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")

    assert String.contains?(response.body, "\"Host\": \"httpbin.org\"")
  end

  # RESPONSE

  test "decodes correct status" do
    request = Raxx.request(:GET, "/status/503")
    request = %{request | authority: "httpbin.org"}

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    assert response.status == 503
  end

  test "decodes response headers" do
    request = Raxx.request(:GET, "/response-headers?lowercase=foo&UPPERCASE=BAR")
    request = %{request | authority: "httpbin.org"}

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    assert "foo" == :proplists.get_value("lowercase", response.headers)
    assert "BAR" == :proplists.get_value("uppercase", response.headers)
  end

  # TODO use delay to test timeout
  test "decodes response headers auth" do
    # request = Raxx.request(:GET, "/drip?duration=5&code=200&numbytes=5")
    request = Raxx.request(:GET, "/stream/5")
    request = %{request | authority: "httpbin.org"}

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    |> IO.inspect()
    assert "foo" == :proplists.get_value("lowercase", response.headers)
    assert "BAR" == :proplists.get_value("uppercase", response.headers)
  end
end
