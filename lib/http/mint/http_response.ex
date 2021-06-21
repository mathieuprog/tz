if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tz.HTTP.Mint.HTTPResponse do
    @moduledoc false

    defstruct status_code: nil, headers: nil, body: [], complete?: false

    def parse([{:status, _, status_code} | mint_messages], %__MODULE__{} = http_response) do
      parse(mint_messages, %{http_response | status_code: status_code})
    end

    def parse([{:headers, _, headers} | mint_messages], %__MODULE__{} = http_response) do
      parse(mint_messages, %{http_response | headers: headers})
    end

    def parse([{:data, _, data} | mint_messages], %__MODULE__{} = http_response) do
      parse(mint_messages, %{http_response | body: [data | http_response.body]})
    end

    def parse([{:done, _}], %__MODULE__{} = http_response) do
      body =
        body
        |> Enum.reverse()
        |> Enum.join()

      {:ok, %{http_response | body: body, complete?: true}}
    end

    def parse([], http_response), do: {:ok, http_response}
  end
end
