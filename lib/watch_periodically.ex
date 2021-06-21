defmodule Tz.WatchPeriodically do
  use GenServer
  require Logger
  alias Tz.HTTP
  alias Tz.PeriodsProvider
  alias Tz.Updater

  defp watch() do
    Logger.debug("Tz is checking for IANA time zone database updates")

    case Updater.fetch_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != PeriodsProvider.database_version() do
          link = "https://data.iana.org/time-zones/releases/tzdata#{latest_version}.tar.gz"
          Logger.warn("Tz found a more recent time zone database available for download at #{link}")
        end
      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
    end
  end

  def start_link(_) do
    HTTP.get_http_client!()

    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    watch()

    {:ok, state}
  end

  def handle_info(:work, state) do
    watch()

    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 24 * 60 * 60 * 1000) # In 24 hours
  end
end
