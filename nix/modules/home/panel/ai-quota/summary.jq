# Summarize one provider's quota into a status-bar pill record.
#
#   jq -c -f summary.jq --arg provider codex ai-quota.json
#
# Emits a single object:
#   {present, state, label, countdown, lines, compact_lines, compact_meters}
#   state: ok | warning | critical | error
# …or {present: false} when the provider has no usable accounts.
#
# Pill semantics ("can I keep working with confidence?"):
#   - an account's constraint is its most-exhausted CODING window (codex's
#     separate code-review pool never blocks normal work and is excluded);
#   - the pill shows the best account's constraint, because burning one
#     account to zero costs nothing while another still has headroom;
#   - `label` names the binding window so "5h·98%" never hides that the
#     weekly window is the one actually about to run dry.
#   - `lines` lists every account x every meter for detailed tooltips;
#   - `compact_lines` keeps the quota windows and text progress bars for
#     tooltips that only support text;
#   - `compact_meters` describes the best account's windows for renderers
#     that can draw native progress bars;
#   - `display_meter` is the one window a compact pill should show. Normally it
#     is the binding window; when multiple windows are exhausted it is the one
#     with the latest reset, because earlier resets cannot restore availability.

def bar:
  ((14 * . / 100) | floor) as $f
  | (if $f < 0 then 0 elif $f > 14 then 14 else $f end) as $f
  | ("█" * $f) + ("░" * (14 - $f));

def tag:
  if (. | ascii_downcase) == "weekly" then "wk"
  elif (. | ascii_downcase) == "daily" then "1d"
  elif (. | ascii_downcase) == "monthly" then "mo"
  elif test("^weekly "; "i") then sub("^weekly "; "wk "; "i")
  else
    gsub("-hour"; "h")
    | gsub("-week"; "w")
    | gsub("-day"; "d")
    | gsub("-minute"; "m")
  end;

def meter_tag:
  if (. | ascii_downcase) == "weekly" then "Weekly"
  elif (. | ascii_downcase) == "daily" then "Daily"
  elif (. | ascii_downcase) == "monthly" then "Monthly"
  elif test("^weekly "; "i") then sub("^weekly "; "Weekly "; "i")
  elif test("^[0-9]+-hour$") then
    capture("^(?<n>[0-9]+)-hour$") | "\(.n)h"
  elif test("^[0-9]+-minute$") then
    (capture("^(?<n>[0-9]+)-minute$").n | tonumber) as $minutes
    | if ($minutes % 60) == 0 then
        "\($minutes / 60)h"
      else
        "\($minutes)m"
      end
  else .
  end;

def pill_tag:
  if (. | ascii_downcase) == "weekly" then "WK"
  elif (. | ascii_downcase) == "daily" then "1D"
  elif (. | ascii_downcase) == "monthly" then "MO"
  elif test("^weekly "; "i") then sub("^weekly "; "WK "; "i") | ascii_upcase
  elif test("^[0-9]+-hour$") then
    (capture("^(?<n>[0-9]+)-hour$").n + "H")
  elif test("^[0-9]+-minute$") then
    (capture("^(?<n>[0-9]+)-minute$").n | tonumber) as $minutes
    | if ($minutes % 60) == 0 then
        "\($minutes / 60)H"
      else
        "\($minutes)M"
      end
  else (. | ascii_upcase)
  end;

def window_span:
  (.duration_seconds // 0) as $duration
  | if $duration > 0 then $duration
  elif .label == "daily" then 86400
  elif (.label | test("^weekly($| )"; "i")) then 604800
  elif .label == "monthly" then 2592000
  elif (.label | test("^[0-9]+-minute$")) then
    (.label | capture("^(?<n>[0-9]+)-minute$").n | tonumber) * 60
  elif (.label | test("^[0-9]+-hour$")) then
    (.label | capture("^(?<n>[0-9]+)-hour$").n | tonumber) * 3600
  elif (.label | test("^[0-9]+-day$")) then
    (.label | capture("^(?<n>[0-9]+)-day$").n | tonumber) * 86400
  elif (.label | test("^[0-9]+-week$")) then
    (.label | capture("^(?<n>[0-9]+)-week$").n | tonumber) * 604800
  else 999999999
  end;

def remaining:
  (100 - (.pct // .percent // 0))
  | if . < 0 then 0 elif . > 100 then 100 else . end;

def state:
  if . <= 20 then "critical"
  elif . <= 50 then "warning"
  else "ok"
  end;

def compact_meter:
  (. | remaining) as $remaining
  | {
      label: (.label | meter_tag),
      pill_label: (.label | pill_tag),
      remaining: $remaining,
      reset: (.reset_human // null),
      reset_label: (if .reset_human then "Resets " + .reset_human else "Reset unavailable" end),
      reset_in: (.reset_in // null),
      span: window_span,
      state: ($remaining | state),
    };

def countdown:
  if . == null then "—"
  elif . <= 0 then "now"
  else
    (. | floor) as $seconds
    | ($seconds / 3600 | floor) as $hours
    | ($hours / 24 | floor) as $days
    | ($hours % 24) as $day_hours
    | if $hours >= 48 then
        "\($days)d \($day_hours)h"
      else
        (($seconds % 3600) / 60 | floor) as $minutes
        | ($minutes | tostring | if length < 2 then "0" + . else . end) as $minute_text
        | "\($hours):\($minute_text)"
      end
  end;

def smart_meter:
  . as $meters
  | [$meters[] | select(.remaining <= 0)] as $exhausted
  | if ($exhausted | length) > 0 then
      ($exhausted | max_by(.reset_in // 0))
    else
      ($meters | sort_by(.remaining, .span) | .[0])
    end;

def window_color($accent):
  (if .span >= 2592000 then "Faint" elif .span >= 604800 then "Dim" else "" end) as $dim
  | $accent + $dim;

# Coding-quota meters only; the review pool is displayed but never binds.
def coding:
  [.meters[] | select((.label | ascii_downcase) | startswith("review") | not)];

def meter_line:
  "  \(.label)  \((.pct // .percent // 0) | bar)  \(100 - (.pct // .percent // 0) | round)% left"
  + (if .reset_human then " · resets " + .reset_human else "" end);

def compact_meter_line:
  "\(.label | tag)  \((.pct // .percent // 0) | bar)  \(100 - (.pct // .percent // 0) | round)% left"
  + (if .reset_human then " · resets " + .reset_human else "" end);

def matches_provider($target):
  .provider == $target
  or ($target == "grok" and .provider == "xai")
  or ($target == "xai" and .provider == "grok");

def provider_accent:
  if . == "claude" then "orange"
  elif . == "kimi" then "blue"
  elif . == "codex" then "green"
  elif . == "antigravity" then "gray"
  elif . == "grok" or . == "xai" then "white"
  else "gray"
  end;

. as $root
| ([$root.providers[] | select(matches_provider($provider))] | .[0] // null)
| if . == null then
    { present: false }
  else
    [.accounts[] | select(.error == null and (.meters | length > 0))] as $healthy
    |     [
        $healthy[]
        | . as $account
        | (coding | max_by(.pct // .percent // 0)) as $binding
        | select($binding != null)
        | {account: $account, binding: $binding}
      ] as $ranked
    | if ($ranked | length) == 0 then
        {
          present: true,
          state: "error",
          label: "--",
          lines: ["no usable coding-quota windows"],
          countdown: "—",
          countdown_meter: null,
          display_meter: null,
          compact_lines: ["no usable coding-quota windows"],
          compact_meters: [],
        }
      else
        ($ranked | min_by(.binding.pct // .binding.percent // 0)) as $best
        | ($best.binding | remaining) as $remaining
        | (if $remaining <= 20 then "critical"
          elif $remaining <= 50 then "warning"
          else "ok"
          end) as $state
        | ($provider | provider_accent) as $accent
        | ([$best.account | coding | sort_by(window_span)[] | compact_meter | . + {color: (. | window_color($accent))}]) as $meters
        | ($meters | smart_meter) as $display
        | {
            present: true,
            state: $state,
            remaining: $remaining,
            countdown: ($display.reset_in | countdown),
            countdown_meter: ($display.label // null),
            display_meter: ($display + {
              countdown: ($display.reset_in | countdown),
              color: $accent,
            }),
            label: (
              ($best.binding.label | tag)
              + "·"
              + (($remaining | round) | tostring)
              + "%"
              + (if ($healthy | length) > 1 then
                  "·" + (($healthy | length) | tostring)
                else
                  ""
                end)
            ),
            lines: [
              ([$root.providers[] | select(matches_provider($provider))]
                | .[0]
                | .accounts[]
                | if .error then
                    "✗ \(.name): \(.error)"
                  else
                    (if .subtitle then
                        "● \(.name) · \(.subtitle)"
                      else
                        "● \(.name)"
                      end),
                    (.meters[] | meter_line)
                  end
              )
            ],
            compact_lines: [
              ([$root.providers[] | select(matches_provider($provider))]
                | .[0]
                | .accounts[]
                | select(.error == null)
                | coding[]
                | compact_meter_line
              )
            ],
            compact_meters: $meters,
          }
      end
  end
