defmodule Tz.CompilerRunner do
  @moduledoc false

  all_env = Application.get_all_env(:tz)

  known_env_keys =
    [
      :http_client,
      :data_dir,
      :iana_version,
      :build_dst_periods_until_year,
      :reject_periods_before_year,
      Tz.HTTP.Mint.HTTPClient
    ]

  unknown_env_keys =
    Keyword.drop(all_env, known_env_keys)
    |> Keyword.keys()

  if (unknown_env_keys != []) do
    joined_known_env_keys =
      known_env_keys
      |> Enum.map(& ":#{to_string(&1)}")
      |> Enum.join(", ")

    raise "possible options are #{joined_known_env_keys}"
  end

  data_dir = Application.compile_env(:tz, :data_dir)
  forced_iana_version = Application.compile_env(:tz, :iana_version)

  if forced_iana_version && !Regex.match?(~r/^20[0-9]{2}[a-z]$/, forced_iana_version) do
    raise "the value \"#{forced_iana_version}\" provided for the :iana_version config is invalid"
  end

  if forced_iana_version && !data_dir do
    raise "when setting a specific IANA version to use, " <>
      "the files must be stored in a custom directory via the :data_dir configuration"
  end

  require Tz.Compiler

  Tz.Compiler.compile()
end
