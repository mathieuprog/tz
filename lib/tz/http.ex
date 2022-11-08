defmodule Tz.HTTP do
  http_client =
    if http_client = Application.compile_env(:tz, :http_client) do
      http_client
    else
      unless Code.ensure_loaded?(Mint.HTTP) do
        raise "No HTTP client found. Add `:mint` as a dependency, or pass a custom HTTP client to the config."
      end

      Tz.HTTP.Mint.HTTPClient
    end

  def get_http_client!() do
    unquote(http_client)
  end
end
