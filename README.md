# Tz

Time zone support for Elixir.

The tz library relies on the [time zone database](https://data.iana.org/time-zones/tzdb/) maintained by [IANA](https://www.iana.org).
As of version 0.1.0, tz uses version tzdata2019c of the IANA time zone database.

## Installation

Add `tz` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:tz, "~> 0.1.0"}
  ]
end
```

## Usage

For usage, refer to the [DateTime](https://hexdocs.pm/elixir/DateTime.html#module-time-zone-database) docs.

The time zone database module name is `Tz.TimeZoneDatabase`.

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/tz](https://hexdocs.pm/tz).

