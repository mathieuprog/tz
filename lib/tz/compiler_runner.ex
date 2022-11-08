defmodule Tz.CompilerRunner do
  @moduledoc false

  all_env = Application.get_all_env(:tz)

  known_env =
    [
      :data_dir,
      :http_client,
      :reject_time_zone_periods_before_year,
      :build_time_zone_periods_with_ongoing_dst_changes_until_year
    ]

  unknown_env = Keyword.drop(all_env, known_env)

  if (unknown_env != []) do
    raise "possible options are #{Enum.join(unknown_env, ", ")}"
  end

  require Tz.Compiler

  Tz.Compiler.compile()
end
