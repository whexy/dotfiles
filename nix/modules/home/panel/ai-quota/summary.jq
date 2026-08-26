# Summarize one provider's quota into a status-bar pill record.
#
#   jq -c -f summary.jq --arg provider codex ai-quota.json
#
# Emits a single object:
#   {present, state, label, lines, compact_lines, compact_meters}
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
#     that can draw native progress bars.

def bar:
  ((14 * . / 100) | floor) as $f
  | (if $f < 0 then 0 elif $f > 14 then 14 else $f end) as $f
  | ("█" * $f) + ("░" * (14 - $f));

def tag:
  gsub("-hour"; "h")
  | gsub("-week"; "w")
  | gsub("-day"; "d")
  | gsub("-minute"; "m")
  | gsub("^weekly$"; "wk")
  | gsub("^daily$"; "1d");

def meter_tag:
  if . == "weekly" then "Weekly"
  elif . == "daily" then "Daily"
  elif . == "monthly" then "Monthly"
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

def window_span:
  if .label == "daily" then 86400
  elif .label == "weekly" then 604800
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
  (100 - (.pct // 0))
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
      remaining: $remaining,
      reset: (.reset_human // null),
      state: ($remaining | state),
    };

# Coding-quota meters only; the review pool is displayed but never binds.
def coding:
  [.meters[] | select((.label | ascii_downcase) | startswith("review") | not)];

def meter_line:
  "  \(.label)  \(.pct | bar)  \(100 - .pct | round)% left"
  + (if .reset_human then " · resets " + .reset_human else "" end);

def compact_meter_line:
  "\(.label | tag)  \(.pct | bar)  \(100 - .pct | round)% left"
  + (if .reset_human then " · resets " + .reset_human else "" end);

. as $root
| ([$root.providers[] | select(.provider == $provider)] | .[0] // null)
| if . == null then
    { present: false }
  else
    [.accounts[] | select(.error == null and (.meters | length > 0))] as $healthy
    |     [
        $healthy[]
        | . as $account
        | (coding | max_by(.pct)) as $binding
        | select($binding != null)
        | {account: $account, binding: $binding}
      ] as $ranked
    | if ($ranked | length) == 0 then
        {
          present: true,
          state: "error",
          label: "--",
          lines: ["no usable coding-quota windows"],
          compact_lines: ["no usable coding-quota windows"],
          compact_meters: [],
        }
      else
        ($ranked | min_by(.binding.pct)) as $best
        | ($best.binding | remaining) as $remaining
        | (if $remaining <= 20 then "critical"
          elif $remaining <= 50 then "warning"
          else "ok"
          end) as $state
        | {
            present: true,
            state: $state,
            remaining: $remaining,
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
              ([$root.providers[] | select(.provider == $provider)]
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
              ([$root.providers[] | select(.provider == $provider)]
                | .[0]
                | .accounts[]
                | select(.error == null)
                | coding[]
                | compact_meter_line
              )
            ],
            compact_meters: [$best.account | coding | sort_by(window_span)[] | compact_meter],
          }
      end
  end
