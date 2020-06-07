if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tz.UpdatePeriodically do
    use GenServer
    require Logger
    alias Tz.Updater

    defp maybe_recompile() do
      Logger.debug("Tz is checking for IANA time zone database updates")

      Updater.maybe_recompile()
    end

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{})
    end

    def init(state) do
      maybe_recompile()

      {:ok, state}
    end

    def handle_info(:work, state) do
      maybe_recompile()

      schedule_work()
      {:noreply, state}
    end

    defp schedule_work() do
      Process.send_after(self(), :work, 24 * 60 * 60 * 1000) # In 24 hours
    end
  end
end
