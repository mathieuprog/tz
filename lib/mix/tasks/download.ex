defmodule Mix.Tasks.Tz.Download do
  use Mix.Task

  alias Tz.IanaDataDir
  alias Tz.Updater

  @shortdoc "Downloads the IANA time zone data."
  def run(command_line_args) do
    {version, dir} = command_line_args(command_line_args)

    dir = dir || IanaDataDir.dir()

    case Updater.update_tz_database(version, dir) do
      :error ->
        Mix.raise("failed to download IANA data for version #{version}")

      {:ok, dir} ->
        Mix.shell().info(
          "IANA time zone data for version #{version} has been extracted into #{dir}"
        )
    end
  end

  defp command_line_args([]) do
    {fetch_latest_version(), nil}
  end

  defp command_line_args([version]) do
    {version(version), nil}
  end

  defp command_line_args([version, dir]) do
    unless File.exists?(dir) do
      Mix.raise("path #{dir} doesn't exist")
    end

    {version(version), dir}
  end

  defp command_line_args(_) do
    Mix.raise(
      "command may have two optional arguments: the tz data version and the destination directory"
    )
  end

  defp version("latest") do
    fetch_latest_version()
  end

  defp version(version) do
    unless Regex.match?(~r/^20[0-9]{2}[a-z]$/, version) do
      Mix.raise("invalid version: #{version}")
    end

    version
  end

  defp fetch_latest_version() do
    case Updater.fetch_latest_iana_tz_version() do
      {:ok, version} ->
        version

      :error ->
        Mix.raise("failed to read the latest version of the IANA time zone database")
    end
  end
end
