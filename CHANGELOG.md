# Changelog

## 0.25.x

* Fix the bug that occurs when the maximum available year in an IANA rule exceeds
  the limit set by the 'max' rule.

## 0.24.x

* Handle negative years
* Convert non-iso datetime to iso

## 0.23.x

* Fix warnings
* Change option names:
  * `:reject_time_zone_periods_before_year` to<br>
    `:reject_periods_before_year`
  * `:build_time_zone_periods_with_ongoing_dst_changes_until_year` to<br>
    `:build_dst_periods_until_year`

* Add a mix task to download the IANA time zone data for a given version
## 0.22.x

* Add a mix task to download the IANA time zone data for a given version

## 0.21.x

  * Allow to configure the schedulers:
    * `Tz.UpdatePeriodically` may receive the option `:interval_in_days`
    * `Tz.WatchPeriodically` may receive the options `:interval_in_days` and `on_update`
  * Fixed: schedulers were only running once...
