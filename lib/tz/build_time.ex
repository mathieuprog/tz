defmodule Tz.BuildTime do
  @moduledoc false

  # The instant a build is stamped with. Reproducible builds set
  # SOURCE_DATE_EPOCH (https://reproducible-builds.org/specs/source-date-epoch/)
  # so that two builds of the same sources produce the same bytes.
  def utc_now do
    case System.get_env("SOURCE_DATE_EPOCH") do
      nil ->
        DateTime.utc_now()

      epoch ->
        case Integer.parse(epoch) do
          {seconds, ""} ->
            DateTime.from_unix!(seconds)

          _ ->
            raise ArgumentError,
                  "SOURCE_DATE_EPOCH must be an integer number of seconds, got: #{inspect(epoch)}"
        end
    end
  end
end
