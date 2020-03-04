defmodule Tz.WatchPeriodically do
  use GenServer

  require Logger

  alias Tz.PeriodsProvider
  alias Tz.HTTP.HTTPClient
  alias Tz.HTTP.HTTPResponse

  def start_link(_) do
    unless Code.ensure_loaded?(Mint.HTTP) do
      raise "Add mint to mix.exs to enable automatic time zone data updates"
    end

    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    Logger.debug("Tz is checking for IANA time zone database updates")

    case fetch_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != PeriodsProvider.version() do
          link = "https://data.iana.org/time-zones/releases/tzdata#{latest_version}.tar.gz"
          Logger.warn("Tz found a more recent time zone database available for download at #{link}")
        end
      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
    end

    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 24 * 60 * 60 * 1000) # In 24 hours
  end

  defp fetch_iana_tz_version() do
    case HTTPClient.request("GET", "/time-zones/tzdb/version", hostname: "data.iana.org") do
      %HTTPResponse{body: body, status_code: 200} ->
        {:ok, body |> List.first() |> String.trim()}
      _ ->
        :error
    end
  end
end
