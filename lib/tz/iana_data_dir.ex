defmodule Tz.IanaDataDir do
  @moduledoc false

  require Logger

  def dir(), do: Application.get_env(:tz, :data_dir) || to_string(:code.priv_dir(:tz))

  def forced_iana_version(), do: Application.get_env(:tz, :iana_version)

  defp tzdata_dir_name(parent_dir) do
    tz_data_dirs =
      File.ls!(parent_dir)
      |> Enum.filter(&Regex.match?(~r/^tzdata20[0-9]{2}[a-z]$/, &1))

    if tz_data_dirs != [] do
      latest_version = Enum.max(tz_data_dirs)

      version =
        if forced_version = forced_iana_version() do
          case Enum.find(tz_data_dirs, & &1 == "tzdata#{forced_version}") do
            nil -> Logger.warn("Tz is compiling with version #{latest_version}. Download version #{forced_version} (run `mix tz.download #{forced_version}`) and compile :tz again.")
            version -> version
          end
        end

      unless version do
        latest_version
      end
    end
  end

  def tzdata_dir_path() do
    if dir_name = tzdata_dir_name(dir()) do
      Path.join(dir(), dir_name)
    end
  end

  def tzdata_version() do
    if dir_name = tzdata_dir_name(dir()) do
      "tzdata" <> version = dir_name
      version
    end
  end

  def maybe_copy_iana_files_to_custom_dir() do
    cond do
      tzdata_version() ->
        nil

      to_string(:code.priv_dir(:tz)) == dir() ->
        raise "tzdata files not found"

      true ->
        if dir_name = tzdata_dir_name(to_string(:code.priv_dir(:tz))) do
          File.cp_r!(Path.join(:code.priv_dir(:tz), dir_name), Path.join(dir(), dir_name))
          # TODO check that the right version is copied?
        else
          raise "tzdata files not found"
        end
    end
  end

  def extract_tzdata_into_dir(version, content, dir \\ dir()) do
    tmp_archive_path = Path.join(dir, "tzdata#{version}.tar.gz")
    tzdata_dir_name = "tzdata#{version}"
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
      {:cwd, Path.join(dir, tzdata_dir_name) |> String.to_charlist()},
      {:files, files_to_extract}
    ])

    :ok = File.rm!(tmp_archive_path)
  end

  def delete_tzdata_dir(version) do
    if version != forced_iana_version() do
      Path.join(dir(), "tzdata#{version}")
      |> File.rm_rf!()
    end
  end
end
