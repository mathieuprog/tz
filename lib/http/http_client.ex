defmodule Tz.HTTP.HTTPClient do
  @callback request(String.t(), String.t()) :: struct

  import Tz.HTTP

  def request(hostname, path) do
    if get_http_client!() do
      get_http_client!().request(hostname, path)
    end
  end
end
