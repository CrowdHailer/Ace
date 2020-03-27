defmodule Ace.HTTP.H2SpecTest do
  use ExUnit.Case

  @moduletag :ci

  @h2spec_base_url "https://github.com/summerwind/h2spec/releases/download/"
  @h2spec_version "v2.4.0"
  @h2spec_dir "test/support/h2spec/"
  @h2spec_archive_destination "#{@h2spec_dir}h2spec_#{@h2spec_version}.tar.gz"
  @h2spec_executable_destination "#{@h2spec_dir}h2spec"

  setup do
    h2spec_path =
      case {System.fetch_env("H2SPEC_PATH"), System.find_executable("h2spec")} do
        {:error, nil} ->
          maybe_fetch_h2spec()
          @h2spec_executable_destination

        {{:ok, path}, _} ->
          path

        {:error, path} ->
          path
      end

    {:ok, %{h2spec_path: h2spec_path}}
  end

  test "run h2spec", %{h2spec_path: h2spec_path} do
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {MyApp, %{greeting: "Hello"}},
        port: 0,
        certfile: Support.test_certfile(),
        keyfile: Support.test_keyfile()
      )

    {:ok, port} = Ace.HTTP.Service.port(service)

    {result, exit_status} =
      System.cwd()
      |> Path.join(@h2spec_executable_destination)
      |> System.cmd([
        "--tls",
        "--insecure",
        "--port",
        Integer.to_string(port)
      ])

    GenServer.stop(service)
    assert exit_status == 0, "h2spec failed\n#{result}"
  end

  defp maybe_fetch_h2spec() do
    if not File.exists?(@h2spec_archive_destination) do
      fetch_h2spec()
    else
      :ok
    end
  end

  defp fetch_h2spec() do
    download()
    decompress_tar_gz()
    :ok
  end

  defp download() do
    Application.ensure_all_started(:httpc)
    url = String.to_charlist(h2spec_url())
    dest = String.to_charlist(@h2spec_archive_destination)

    {:ok, :saved_to_file} = :httpc.request(:get, {url, []}, [], stream: dest)
    Application.stop(:httpc)
    :ok
  end

  defp decompress_tar_gz do
    File.rm(@h2spec_executable_destination)
    :ok = :erl_tar.extract(@h2spec_archive_destination, [:compressed, {:cwd, @h2spec_dir}])
    true = File.exists?(@h2spec_executable_destination)
  end

  defp h2spec_url do
    os_type =
      case :os.type() do
        {:unix, :darwin} ->
          "darwin"

        {:unix, _} ->
          "linux"

        {:win32, _} ->
          "windows"

        _ ->
          nil
      end

    "#{@h2spec_base_url}#{@h2spec_version}/h2spec_#{os_type}_amd64.tar.gz"
  end
end
