defmodule Tz.CompilerRunner do
  @moduledoc false

  all_env = Application.get_all_env(:tz)

  known_env_keys =
    [
      :data_dir,
      :http_client,
      :reject_time_zone_periods_before_year,
      :build_time_zone_periods_with_ongoing_dst_changes_until_year
    ]

  unknown_env_keys =
    Keyword.drop(all_env, known_env_keys)
    |> Keyword.keys()

  if (unknown_env_keys != []) do
    raise "possible options are #{Enum.join(unknown_env_keys, ", ")}"
  end

  require Tz.Compiler

  Tz.Compiler.compile()
end
