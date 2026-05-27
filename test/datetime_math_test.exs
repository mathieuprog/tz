defmodule DateTimeMathTest do
  use ExUnit.Case, async: true

  @timezone "America/Fortaleza"
  @datetime DateTime.from_naive!(~N[2025-04-15 00:00:01.000000], @timezone, Tz.TimeZoneDatabase)
  @added_second DateTime.add(@datetime, +1, :second, Tz.TimeZoneDatabase)
  @minus_second DateTime.add(@datetime, -1, :second, Tz.TimeZoneDatabase)

  describe "nanosecond" do
    test "adds 1 second with nanosecond unit" do
      amount = System.convert_time_unit(+1, :second, :nanosecond)
      unit = :nanosecond
      assert DateTime.add(@datetime, amount, unit, Tz.TimeZoneDatabase) == @added_second
    end

    test "subtracts 1 second with nanosecond unit" do
      amount = System.convert_time_unit(-1, :second, :nanosecond)
      unit = :nanosecond
      assert DateTime.add(@datetime, amount, unit, Tz.TimeZoneDatabase) == @minus_second
    end
  end

  describe "strictly positive integer with units ranging from decisecond (10^-1s) to Planck time (10^-44s)" do
    # To understand how this units work see:
    # - https://hexdocs.pm/elixir/1.18.2/System.html#t:time_unit/0
    # - https://en.wikipedia.org/wiki/Orders_of_magnitude_(time)
    @units_in_parts_per_second Enum.map(1..44, &System.convert_time_unit(1, :second, 10 ** &1))

    test "adds 1 second" do
      Enum.each(@units_in_parts_per_second, fn parts_per_second ->
        amount = +parts_per_second
        unit = parts_per_second
        assert DateTime.add(@datetime, amount, unit, Tz.TimeZoneDatabase) == @added_second
      end)
    end

    test "subtracts 1 second" do
      Enum.each(@units_in_parts_per_second, fn parts_per_second ->
        amount = -parts_per_second
        unit = parts_per_second
        assert DateTime.add(@datetime, amount, unit, Tz.TimeZoneDatabase) == @minus_second
      end)
    end
  end
end
