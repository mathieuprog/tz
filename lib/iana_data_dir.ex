defmodule Tz.IanaDataDir do
  @regex_tzdata_dir_name ~r/^tzdata20[0-9]{2}[a-z]$/
  @custom_data_dir Application.get_env(:tz, :data_dir)

  defp dir(), do: @custom_data_dir || :code.priv_dir(:tz)

  def tzdata_dir_name(parent_dir \\ dir()) do
    tz_data_dirs =
      File.ls!(parent_dir)
      |> Enum.filter(&Regex.match?(@regex_tzdata_dir_name, &1))

    if tz_data_dirs != [] do
      Enum.max(tz_data_dirs)
    else
      nil
    end
  end

  def tzdata_dir_path() do
    if dir_name = tzdata_dir_name() do
      Path.join(dir(), dir_name)
    end
  end

  def tzdata_version() do
    if dir_name = tzdata_dir_name() do
      "tzdata" <> version = dir_name
      version
    end
  end

  def maybe_copy_iana_files_to_custom_dir() do
    cond do
      tzdata_version() ->
        nil

      :code.priv_dir(:tz) == dir() ->
        raise "tzdata files not found"

      true ->
        if dir_name = tzdata_dir_name(:code.priv_dir(:tz)) do
          File.cp_r!(Path.join(:code.priv_dir(:tz), dir_name), Path.join(dir(), dir_name))
        else
          raise "tzdata files not found"
        end
    end
  end

  def extract_tzdata_into_dir(version, content) do
    tmp_archive_path = Path.join(dir(), "tzdata#{version}.tar.gz")
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
      {:cwd, Path.join(dir(), tzdata_dir_name) |> String.to_charlist()},
      {:files, files_to_extract}
    ])

    :ok = File.rm!(tmp_archive_path)
  end

  def delete_tzdata_dir(version) do
    Path.join(dir(), "tzdata#{version}")
    |> File.rm_rf!()
  end
end
