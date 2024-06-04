defmodule Tz.Updater do
  require Logger

  alias Tz.Compiler
  alias Tz.HTTP
  alias Tz.HTTP.HTTPResponse
  alias Tz.IanaDataDir
  alias Tz.PeriodsProvider

  @doc """
  Recompiles the period maps only if more recent IANA data is available.
  """
  def maybe_recompile() do
    {_, latest_tz_version} = maybe_update_tz_database_to_latest_version()

    if latest_tz_version != PeriodsProvider.iana_version() do
      if IanaDataDir.forced_iana_version() do
        raise "cannot update time zone periods as version #{IanaDataDir.forced_iana_version()} has been forced through the :iana_version config"
      end

      Logger.info("Tz is recompiling the time zone periods...")
      Code.compiler_options(ignore_module_conflict: true)
      Compiler.compile()
      Code.compiler_options(ignore_module_conflict: false)
      Logger.info("Tz compilation done")
    end
  end

  defp maybe_update_tz_database_to_latest_version() do
    latest_version_saved = IanaDataDir.latest_tzdata_version()

    case fetch_latest_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != latest_version_saved &&
             latest_version != PeriodsProvider.iana_version() do
          case update_tz_database(latest_version) do
            {:ok, _dir} ->
              IanaDataDir.delete_tzdata_dir(latest_version_saved)
              {:updated, latest_version}

            :error ->
              {:error, latest_version_saved}
          end
        else
          {:already_latest, latest_version}
        end

      :error ->
        {:error, latest_version_saved}
    end
  end

  @doc false
  def fetch_latest_iana_tz_version() do
    Logger.info(
      "Tz is fetching the latest IANA time zone data version at https://data.iana.org/time-zones/tzdb/version"
    )

    case HTTP.get_http_client!().request("data.iana.org", "/time-zones/tzdb/version") do
      %HTTPResponse{body: body, status_code: 200} ->
        version = body |> String.trim()
        Logger.info("Latest version of the IANA time zone data is #{version}")
        {:ok, version}

      _ ->
        Logger.error("Tz failed to read the latest version of the IANA time zone data")
        :error
    end
  end

  @doc false
  def update_tz_database(version, dir \\ IanaDataDir.dir())
      when is_binary(version) and is_binary(dir) do
    case download_tz_database(version) do
      {:ok, content} ->
        tzdata_dir = IanaDataDir.extract_tzdata_into_dir(version, content, dir)
        Logger.info("IANA time zone data extracted into #{tzdata_dir}")
        {:ok, tzdata_dir}

      :error ->
        :error
    end
  end

  defp download_tz_database(version) do
    Logger.info(
      "Tz is downloading the IANA time zone data version #{version} at https://data.iana.org/time-zones/releases/tzdata#{version}.tar.gz"
    )

    case HTTP.get_http_client!().request(
           "data.iana.org",
           "/time-zones/releases/tzdata#{version}.tar.gz"
         ) do
      %HTTPResponse{body: body, status_code: 200} ->
        Logger.info("Tz download done")
        {:ok, body}

      _ ->
        Logger.error("Tz failed to download the latest IANA time zone data (version #{version})")
        :error
    end
  end
end
