# Tz

Time zone support for Elixir.

The Elixir standard library does not ship with a time zone database. As a result, the functions in the `DateTime`
module can, by default, only operate on datetimes in the UTC time zone. Alternatively (and
[deliberately](https://elixirforum.com/t/14743)), the standard library relies on
third-party libraries, such as `tz`, to bring in time zone support and deal with datetimes in other time zones than UTC.

The `tz` library relies on the [time zone database](https://data.iana.org/time-zones/tzdb/) maintained by
[IANA](https://www.iana.org). As of version 0.7.3, `tz` uses version _tzdata2019c_ of the IANA time zone database.

## Features

### Battle-tested

The `tz` library is tested against nearly 10 million past dates, which includes most of all possible imaginable
edge cases.

### Pre-compiled time zone data

Time zone periods are deducted from the [IANA time zone data](https://data.iana.org/time-zones/tzdb/). A period is a
period of time where a certain offset is observed. Example: in Belgium, from 31 March 2019 until 27 October 2019, clock
went forward by 1 hour; this means that during this period, Belgium observed a total offset of 2 hours from UTC time.

The time zone periods are computed and made available in Elixir maps during compilation time, to be consumed by the
[DateTime](https://hexdocs.pm/elixir/DateTime.html#module-time-zone-database) module.

### Automatic time zone data updates

`tz` can watch for IANA time zone database updates and automatically recompile the time zone periods.

To enable automatic updates, add `Tz.UpdatePeriodically` as a child in your supervisor:

```
{Tz.UpdatePeriodically, []}
```

If you do not wish to update automatically, but still wish be alerted for new upcoming IANA updates, add
`Tz.WatchPeriodically` as a child in your supervisor:

```
{Tz.WatchPeriodically, []}
```

Lastly, add the http client `mint` and ssl certificate store `castore` into your `mix.exs` file:

```
defp deps do
  [
    {:castore, "~> 0.1.5"},
    {:mint, "~> 1.0"},
    {:tz, "~> 0.7.3"}
  ]
end
```

## Usage

To use the `tz` database, either configure it via configuration:
```
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

or by calling `Calendar.put_time_zone_database/1`:
```
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
```

or by passing the module name `Tz.TimeZoneDatabase` directly to the functions that need a time zone database:
```
DateTime.now("America/Sao_Paulo", Tz.TimeZoneDatabase)
```

Refer to the [DateTime API](https://hexdocs.pm/elixir/DateTime.html) for more details
about handling datetimes with time zones.

## Performance tweaks

`tz` provides two environment options to tweak performance.

You can decrease **compilation time**, by rejecting time zone periods before a given year:

```
config :tz, reject_time_zone_periods_before_year: 2010
```

By default, no periods are rejected.

You can decrease **period lookup time** for periods in the future (that have ongoing DST changes), by specifying until
what year those periods have to be computed:

```
config :tz, build_time_zone_periods_with_ongoing_dst_changes_until_year: 20 + NaiveDateTime.utc_now().year
```

By default, periods are computed until 5 years from compilation time.

## Installation

Add `tz` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:tz, "~> 0.7.3"}
  ]
end
```

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/tz](https://hexdocs.pm/tz).
