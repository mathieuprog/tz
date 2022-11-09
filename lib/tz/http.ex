defmodule Tz.HTTP do
  http_client =
    if http_client = Application.compile_env(:tz, :http_client) do
      http_client
    else
      if Code.ensure_loaded?(Mint.HTTP) do
        Tz.HTTP.Mint.HTTPClient
      end
    end

  @doc """
  Return the http client module configured for tz.
  """
  def get_http_client!() do
    unless unquote(http_client) do
      raise "No HTTP client found. Add `:mint` as a dependency, or pass a custom HTTP client to the config."
    end

    unquote(http_client)
  end
end
