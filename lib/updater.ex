if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tz.Updater do
    @moduledoc false

    require Logger

    alias Tz.Compiler
    alias Tz.PeriodsProvider
    alias Tz.HTTP.HTTPClient
    alias Tz.HTTP.HTTPResponse

    def maybe_recompile() do
      if maybe_update_tz_database() == :updated do
        Logger.info("Tz is recompiling time zone periods...")
        Code.compiler_options(ignore_module_conflict: true)
        Compiler.compile()
        Code.compiler_options(ignore_module_conflict: false)
        Logger.info("Tz compilation done")
      end
    end

    def fetch_iana_tz_version() do
      case HTTPClient.request("GET", "/time-zones/tzdb/version", hostname: "data.iana.org") do
        %HTTPResponse{body: body, status_code: 200} ->
          {:ok, body |> List.first() |> String.trim()}
        _ ->
          :error
      end
    end

    defp maybe_update_tz_database() do
      case fetch_iana_tz_version() do
        {:ok, latest_version} ->
          if latest_version != PeriodsProvider.database_version() do
            case update_tz_database(latest_version) do
              :ok ->
                delete_tz_database(PeriodsProvider.database_version())
                :updated
              _ -> :error
            end
          end
        :error ->
          Logger.error("Tz failed to read the latest version of the IANA time zone database")
          :no_update
      end
    end

    defp update_tz_database(version) do
      case download_tz_database(version) do
        {:ok, content} ->
          extract_tz_database(version, content)
          :ok
        :error ->
          Logger.error("Tz failed to download the latest archived IANA time zone database (version #{version})")
          :error
      end
    end

    defp download_tz_database(version) do
      Logger.info("Tz is downloading the latest IANA time zone database (version #{version})...")
      case HTTPClient.request("GET", "/time-zones/releases/tzdata#{version}.tar.gz", hostname: "data.iana.org") do
        %HTTPResponse{body: body, status_code: 200} ->
          Logger.info("Tz download done")
          {:ok, body}
        _ ->
          :error
      end
    end

    defp extract_tz_database(version, content) do
      tmp_archive_path = Path.join(:code.priv_dir(:tz), "tzdata#{version}.tar.gz")
      tz_data_dir = "tzdata#{version}"
      :ok = File.write!(tmp_archive_path, content)

      files_to_extract = [
        'africa',
        'antarctica',
        'asia',
        'australasia',
        'backward',
        'etcetera',
        'europe',
        'northamerica',
        'southamerica',
        'iso3166.tab',
        'zone1970.tab'
      ]
      :ok = :erl_tar.extract(tmp_archive_path, [
        :compressed,
        {:cwd, Path.join(:code.priv_dir(:tz), tz_data_dir)},
        {:files, files_to_extract}
      ])

      :ok = File.rm!(tmp_archive_path)
    end

    defp delete_tz_database(version) do
      Path.join(:code.priv_dir(:tz), "tzdata#{version}")
      |> File.rm_rf!()
    end
  end
end
