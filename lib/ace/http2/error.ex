defmodule Ace.HTTP2.Errors do
  @moduledoc false

  @defined [
    {0x0, :no_error},
    {0x1, :protocol_error},
    {0x2, :internal_error},
    {0x3, :flow_control_error},
    {0x4, :settings_timeout},
    {0x5, :stream_closed},
    {0x6, :frame_size_error},
    {0x7, :refused_stream},
    {0x8, :cancel},
    {0x9, :compression_error},
    {0xa, :connect_error},
    {0xb, :enhance_your_calm},
    {0xc, :inadequate_security},
    {0xd, :http_1_1_required},
  ]

  for {code, error} <- @defined do
    def encode(unquote(error)), do: unquote(code)
  end

  for {code, error} <- @defined do
    def decode(unquote(code)), do: unquote(error)
  end
  def decode(_), do: :unknown_error_code
end
