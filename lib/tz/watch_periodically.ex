defmodule Tz.WatchPeriodically do
  @moduledoc """
  A process watching for IANA data updates periodically.
  """

  use GenServer
  require Logger
  alias Tz.HTTP
  alias Tz.PeriodsProvider
  alias Tz.Updater

  # Logger.warn/1 is deprecated on Elixir 1.15 but since its
  # a macro we can replace it without performance penalty by
  # selecting the available Logger macro at compile time.
  defmacrop logger_warning(message) do
    if Code.ensure_loaded?(Logger) && function_exported?(Logger, :"MACRO-warning", 2) do
      quote do
        Logger.warning(unquote(message))
      end
    else
      quote do
        Logger.warn(unquote(message))
      end
    end
  end

  defp watch(on_update_callback) do
    Logger.debug("Tz is checking for IANA time zone database updates")

    case Updater.fetch_latest_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != PeriodsProvider.iana_version() do
          link = "https://data.iana.org/time-zones/releases/tzdata#{latest_version}.tar.gz"

          logger_warning(
            "Tz found a more recent time zone database available for download at #{link}"
          )

          on_update_callback && on_update_callback.(latest_version)
        end

      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
    end
  end

  @doc false
  def start_link(opts) do
    HTTP.get_http_client!()

    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    {:ok, %{opts: opts}, {:continue, :work}}
  end

  @doc false
  def handle_continue(:work, %{opts: opts}) do
    watch(opts[:on_update])
    schedule_work(opts[:interval_in_days])
    {:noreply, %{opts: opts}}
  end

  @doc false
  def handle_info(:work, %{opts: opts}) do
    watch(opts[:on_update])
    schedule_work(opts[:interval_in_days])
    {:noreply, %{opts: opts}}
  end

  defp schedule_work(interval_in_days) do
    interval_in_days = interval_in_days || 1
    Process.send_after(self(), :work, interval_in_days * 24 * 60 * 60 * 1000)
  end
end
