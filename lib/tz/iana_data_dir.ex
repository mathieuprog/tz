defmodule Tz.IanaDataDir do
  @moduledoc false

  def dir(), do: Application.get_env(:tz, :data_dir) || to_string(:code.priv_dir(:tz))

  def forced_iana_version(), do: Application.get_env(:tz, :iana_version)

  defp latest_dir_name([]), do: nil
  defp latest_dir_name(dir_names) do
    Enum.max(dir_names)
  end

  defp relevant_dir_name([]), do: nil
  defp relevant_dir_name(dir_names) do
    if forced_version = forced_iana_version() do
      Enum.find(dir_names, & &1 == "tzdata#{forced_version}")
    else
      latest_dir_name(dir_names)
    end
  end

  defp list_dir_names(parent_dir) do
    File.ls!(parent_dir)
    |> Enum.filter(&Regex.match?(~r/^tzdata20[0-9]{2}[a-z]$/, &1))
  end

  def latest_tzdata_dir_name() do
    latest_dir_name(list_dir_names(dir()))
  end

  def relevant_tzdata_dir_name() do
    relevant_dir_name(list_dir_names(dir()))
  end

  def latest_tzdata_dir_path() do
    if dir_name = latest_dir_name(list_dir_names(dir())) do
      Path.join(dir(), dir_name)
    end
  end

  def relevant_tzdata_dir_path() do
    if dir_name = relevant_dir_name(list_dir_names(dir())) do
      Path.join(dir(), dir_name)
    end
  end

  def latest_tzdata_version() do
    if dir_name = latest_dir_name(list_dir_names(dir())) do
      "tzdata" <> version = dir_name
      version
    end
  end

  def relevant_tzdata_version() do
    if dir_name = relevant_dir_name(list_dir_names(dir())) do
      "tzdata" <> version = dir_name
      version
    end
  end

  def maybe_copy_iana_files_to_custom_dir() do
    cond do
      to_string(:code.priv_dir(:tz)) == dir() ->
        nil

      relevant_tzdata_dir_path() ->
        nil

      true ->
        dir_names = list_dir_names(to_string(:code.priv_dir(:tz)))

        cond do
          dir_name = relevant_dir_name(dir_names) ->
            File.cp_r!(Path.join(:code.priv_dir(:tz), dir_name), Path.join(dir(), dir_name))

          dir_name = latest_dir_name(dir_names) ->
            File.cp_r!(Path.join(:code.priv_dir(:tz), dir_name), Path.join(dir(), dir_name))

          true ->
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
