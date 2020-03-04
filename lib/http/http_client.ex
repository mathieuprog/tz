if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tz.HTTP.HTTPClient do
    alias Mint.HTTP
    alias Tz.HTTP.HTTPResponse

    def request(method, path, opts) do
      hostname = Keyword.fetch!(opts, :hostname)
      headers = Keyword.get(opts, :headers, [])

      {:ok, conn} = HTTP.connect(:https, hostname, 443, opts)
      {:ok, conn, _} = HTTP.request(conn, method, path, headers, nil)

      {:ok, response = %HTTPResponse{}} = recv_response(conn)
      {:ok, _conn} = HTTP.close(conn)

      response
    end

    defp recv_response(conn, http_response \\ %HTTPResponse{}) do
      receive do
        message ->
          {:ok, conn, mint_messages} = HTTP.stream(conn, message)

          case HTTPResponse.parse(mint_messages, http_response) do
            {:ok, http_response = %HTTPResponse{complete?: true}} ->
              {:ok, http_response}

            {:ok, http_response} ->
              recv_response(conn, http_response)

            error ->
              error
          end
      end
    end
  end
end
