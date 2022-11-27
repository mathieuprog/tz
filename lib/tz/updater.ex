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
    IanaDataDir.maybe_copy_iana_files_to_custom_dir()

    {_, saved_tz_version} = maybe_update_tz_database_to_latest_version()

    # TODO support for forced iana version

    if saved_tz_version != PeriodsProvider.iana_version() do
      Logger.info("Tz is recompiling time zone periods...")
      Code.compiler_options(ignore_module_conflict: true)
      Compiler.compile()
      Code.compiler_options(ignore_module_conflict: false)
      Logger.info("Tz compilation done")
    end
  end

  defp maybe_update_tz_database_to_latest_version() do
    latest_version_saved = IanaDataDir.tzdata_version()

    case fetch_latest_iana_tz_version() do
      {:ok, latest_version} ->
        if latest_version != latest_version_saved do
          Logger.info("Tz is downloading the IANA time zone database (version #{latest_version})...")
          case update_tz_database(latest_version) do
            {:ok, dir} ->
              Logger.info("Tz download done (into #{dir})")
              IanaDataDir.delete_tzdata_dir(latest_version_saved)
              {:updated, latest_version}

            :error ->
              Logger.error("Tz failed to download the latest archived IANA time zone database (version #{latest_version})")
              {:error, latest_version_saved}
          end
        else
          {:already_latest, latest_version}
        end

      :error ->
        Logger.error("Tz failed to read the latest version of the IANA time zone database")
        {:error, latest_version_saved}
    end
  end

  @doc false
  def fetch_latest_iana_tz_version() do
    case HTTP.get_http_client!().request("data.iana.org", "/time-zones/tzdb/version") do
      %HTTPResponse{body: body, status_code: 200} ->
        {:ok, body |> String.trim()}

      _ ->
        :error
    end
  end

  @doc false
  def update_tz_database(version, dir \\ IanaDataDir.dir())
      when is_binary(version) and is_binary(dir) do
    case download_tz_database(version) do
      {:ok, content} ->
        IanaDataDir.extract_tzdata_into_dir(version, content, dir)
        {:ok, dir}

      :error ->
        :error
    end
  end

  defp download_tz_database(version) do
    case HTTP.get_http_client!().request("data.iana.org", "/time-zones/releases/tzdata#{version}.tar.gz") do
      %HTTPResponse{body: body, status_code: 200} ->
        {:ok, body}

      _ ->
        :error
    end
  end
end
