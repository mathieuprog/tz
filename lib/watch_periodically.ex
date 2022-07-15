defmodule Tz.WatchPeriodically do
  use GenServer
  require Logger
  alias Tz.HTTP
  alias Tz.PeriodsProvider
  alias Tz.Updater

  defp watch(on_update_callback) do
    Logger.debug("Tz is checking for IANA time zone database updates")

    case Updater.fetch_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != PeriodsProvider.iana_version() do
          link = "https://data.iana.org/time-zones/releases/tzdata#{latest_version}.tar.gz"
          Logger.warn("Tz found a more recent time zone database available for download at #{link}")
          on_update_callback && on_update_callback.(latest_version)
        end
      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
    end
  end

  def start_link(opts) do
    HTTP.get_http_client!()

    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    {:ok, %{opts: opts}}
  end

  def handle_info(:work, %{opts: opts}) do
    watch(opts[:on_update])

    schedule_work()
    {:noreply, %{opts: opts}}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 24 * 60 * 60 * 1000) # In 24 hours
  end
end
