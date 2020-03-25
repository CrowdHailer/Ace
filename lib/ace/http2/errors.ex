defmodule Ace.HTTP2.Errors do
  @moduledoc false

  @type error ::
          :no_error
          | :protocol_error
          | :internal_error
          | :flow_control_error
          | :settings_timeout
          | :stream_closed
          | :frame_size_error
          | :refused_stream
          | :cancel
          | :compression_error
          | :connect_error
          | :enhance_your_calm
          | :inadequate_security
          | :http_1_1_required

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
    {0xA, :connect_error},
    {0xB, :enhance_your_calm},
    {0xC, :inadequate_security},
    {0xD, :http_1_1_required}
  ]

  @spec encode(error()) :: 0x0..0xD
  for {code, error} <- @defined do
    def encode(unquote(error)), do: unquote(code)
  end

  @spec decode(0x0..0xD) :: error()
  for {code, error} <- @defined do
    def decode(unquote(code)), do: unquote(error)
  end

  def decode(_), do: :unknown_error_code
end
