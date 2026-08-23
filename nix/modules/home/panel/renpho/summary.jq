def number($value):
  if ($value | type) == "number" then $value else null end;

def date:
  (.localCreatedAt // "----------") | tostring | .[0:10];

def daily:
  sort_by([date, -(.timeStamp // 0)])
  | group_by(date)
  | map(
      .[0] as $newest
      | $newest + {
          localCreatedAt: ($newest | date),
          weight: ([.[].weight | number(.) | select(. != null and . != 0)] | if length > 0 then add / length else null end),
          bmi: ([.[].bmi | number(.) | select(. != null and . != 0)] | if length > 0 then add / length else null end),
          bodyfat: ([.[].bodyfat | number(.) | select(. != null and . != 0)] | if length > 0 then add / length else null end)
        }
    )
  | sort_by(.timeStamp // 0)
  | reverse;

def trend($current; $previous):
  if ($current | type) != "number" or ($previous | type) != "number" then
    { arrow: "", delta: null, state: "flat" }
  elif (($current - $previous) | fabs) < 0.05 then
    { arrow: "→", delta: 0, state: "flat" }
  elif $current < $previous then
    { arrow: "▼", delta: (($previous - $current) * 10 | round / 10), state: "down" }
  else
    { arrow: "▲", delta: (($current - $previous) * 10 | round / 10), state: "up" }
  end;

def row($record; $previous):
  (trend($record.weight; ($previous.weight // null))) as $trend
  | ($record | date) + "  "
    + (if ($record.weight | type) == "number" then ($record.weight * 10 | round / 10 | tostring) + "kg" else "?kg" end) + "  "
    + (if ($record.bmi | type) == "number" then "BMI " + ($record.bmi * 10 | round / 10 | tostring) else "BMI ?" end) + "  "
    + (if ($record.bodyfat | type) == "number" then "BF " + ($record.bodyfat * 10 | round / 10 | tostring) + "%" else "BF ?" end)
    + (if $trend.delta == null then "" elif $trend.state == "flat" then "  →" else "  " + $trend.arrow + ($trend.delta | tostring) end);

if type != "array" or length == 0 then
  {
    present: false,
    state: "stale",
    weight: null,
    bmi: null,
    trend: "",
    delta: null,
    lines: ["no data yet"]
  }
else
  daily as $records
  | $records[0] as $latest
  | ($records[1] // {}) as $previous
  | trend($latest.weight; ($previous.weight // null)) as $trend
  | {
      present: true,
      state: $trend.state,
      weight: $latest.weight,
      bmi: $latest.bmi,
      trend: $trend.arrow,
      delta: $trend.delta,
      lines: [range(0; ([$records | length, $summary_count] | min)) as $i | row($records[$i]; ($records[$i + 1] // {}))]
    }
end
