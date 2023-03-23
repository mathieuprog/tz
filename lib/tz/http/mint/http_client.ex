if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tz.HTTP.Mint.HTTPClient do
    @behaviour Tz.HTTP.HTTPClient

    @moduledoc false

    alias Mint.HTTP
    alias Tz.HTTP.Mint.HTTPResponse, as: MintHTTPResponse
    alias Tz.HTTP.HTTPResponse

    @impl Tz.HTTP.HTTPClient
    def request(hostname, path) do
      opts = Application.get_env(:tz, Tz.HTTP.Mint.HTTPClient, [])

      {:ok, conn} = HTTP.connect(:https, hostname, 443, opts)
      {:ok, conn, _} = HTTP.request(conn, "GET", path, [], nil)

      {:ok, response = %MintHTTPResponse{}} = recv_response(conn)
      {:ok, _conn} = HTTP.close(conn)

      %HTTPResponse{
        status_code: response.status_code,
        body: response.body
      }
    end

    defp recv_response(conn, http_response \\ %MintHTTPResponse{}) do
      receive do
        message ->
          {:ok, conn, mint_messages} = HTTP.stream(conn, message)

          case MintHTTPResponse.parse(mint_messages, http_response) do
            {:ok, http_response = %MintHTTPResponse{complete?: true}} ->
              {:ok, http_response}

            {:ok, http_response} ->
              recv_response(conn, http_response)
          end
      end
    end
  end
end
