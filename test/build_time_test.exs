defmodule Tz.BuildTimeTest do
  use ExUnit.Case

  setup do
    previous = System.get_env("SOURCE_DATE_EPOCH")

    on_exit(fn ->
      if previous,
        do: System.put_env("SOURCE_DATE_EPOCH", previous),
        else: System.delete_env("SOURCE_DATE_EPOCH")
    end)
  end

  test "reads the clock when SOURCE_DATE_EPOCH is unset" do
    System.delete_env("SOURCE_DATE_EPOCH")
    assert DateTime.diff(DateTime.utc_now(), Tz.BuildTime.utc_now()) < 5
  end

  test "stamps the build with SOURCE_DATE_EPOCH when it is set" do
    System.put_env("SOURCE_DATE_EPOCH", "1759276800")
    assert Tz.BuildTime.utc_now() == ~U[2025-10-01 00:00:00Z]
  end

  test "rejects a SOURCE_DATE_EPOCH that is not a number of seconds" do
    System.put_env("SOURCE_DATE_EPOCH", "2025-10-01")
    assert_raise ArgumentError, ~r/SOURCE_DATE_EPOCH/, fn -> Tz.BuildTime.utc_now() end
  end
end
