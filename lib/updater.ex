defmodule Tz.Updater do
  @moduledoc false

  require Logger

  alias Tz.Compiler
  alias Tz.HTTP
  alias Tz.HTTP.HTTPResponse
  alias Tz.IanaDataDir
  alias Tz.PeriodsProvider

  def maybe_recompile() do
    IanaDataDir.maybe_copy_iana_files_to_custom_dir()

    saved_tz_version = get_latest_tz_database()

    if saved_tz_version != PeriodsProvider.iana_version() do
      Logger.info("Tz is recompiling time zone periods...")
      Code.compiler_options(ignore_module_conflict: true)
      Compiler.compile()
      Code.compiler_options(ignore_module_conflict: false)
      Logger.info("Tz compilation done")
    end
  end

  def fetch_iana_tz_version() do
    case HTTP.get_http_client!().request("data.iana.org", "/time-zones/tzdb/version") do
      %HTTPResponse{body: body, status_code: 200} ->
        {:ok, body |> String.trim()}

      _ ->
        :error
    end
  end

  defp get_latest_tz_database() do
    latest_version_saved = IanaDataDir.tzdata_version()

    case fetch_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != latest_version_saved do
          case update_tz_database(latest_version) do
            :ok ->
              IanaDataDir.delete_tzdata_dir(latest_version_saved)
              latest_version

            :error ->
              latest_version_saved
          end
        else
          latest_version
        end

      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
        latest_version_saved
    end
  end

  defp update_tz_database(version) do
    case download_tz_database(version) do
      {:ok, content} ->
        IanaDataDir.extract_tzdata_into_dir(version, content)
        :ok

      :error ->
        Logger.error("Tz failed to download the latest archived IANA time zone database (version #{version})")
        :error
    end
  end

  defp download_tz_database(version) do
    Logger.info("Tz is downloading the latest IANA time zone database (version #{version})...")

    case HTTP.get_http_client!().request("data.iana.org", "/time-zones/releases/tzdata#{version}.tar.gz") do
      %HTTPResponse{body: body, status_code: 200} ->
        Logger.info("Tz download done")
        {:ok, body}

      _ ->
        :error
    end
  end
end
