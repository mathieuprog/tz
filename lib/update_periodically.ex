defmodule Tz.UpdatePeriodically do
  use GenServer
  require Logger
  alias Tz.HTTP
  alias Tz.Updater

  defp maybe_recompile() do
    Logger.debug("Tz is checking for IANA time zone database updates")

    Updater.maybe_recompile()
  end

  def start_link(opts) do
    HTTP.get_http_client!()

    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    maybe_recompile()
    schedule_work(opts[:interval_in_days])
    {:ok, %{}}
  end

  def handle_info(:work, %{opts: opts}) do
    maybe_recompile()
    schedule_work(opts[:interval_in_days])
    {:noreply, %{opts: opts}}
  end

  defp schedule_work(interval_in_days) do
    interval_in_days = interval_in_days || 1
    Process.send_after(self(), :work, interval_in_days * 24 * 60 * 60 * 1000)
  end
end
