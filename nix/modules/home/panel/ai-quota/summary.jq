# Summarize one provider's quota into a status-bar pill record.
#
#   jq -c -f summary.jq --arg provider codex ai-quota.json
#
# Emits a single object:
#   {present, state, label, lines}    state: ok | warning | critical | error
# …or {present: false} when the provider has no usable accounts.
#
# Pill semantics ("can I keep working with confidence?"):
#   - an account's constraint is its most-exhausted CODING window (codex's
#     separate code-review pool never blocks normal work and is excluded);
#   - the pill shows the best account's constraint, because burning one
#     account to zero costs nothing while another still has headroom;
#   - `label` names the binding window so "5h·98%" never hides that the
#     weekly window is the one actually about to run dry.
#   - `lines` lists every account x every meter for the popup/tooltip.

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

# Coding-quota meters only; the review pool is displayed but never binds.
def coding:
  [.meters[] | select((.label | ascii_downcase) | startswith("review") | not)];

def meter_line:
  "  \(.label)  \(.pct | bar)  \(100 - .pct | round)% left"
  + (if .reset_human then " · resets " + .reset_human else "" end);

. as $root
| ([$root.providers[] | select(.provider == $provider)] | .[0] // null)
| if . == null then
    { present: false }
  else
    [.accounts[] | select(.error == null and (.meters | length > 0))] as $healthy
    |     [
        $healthy[]
        | (coding | max_by(.pct)) as $binding
        | select($binding != null)
        | $binding
      ] as $ranked
    | if ($ranked | length) == 0 then
        {
          present: true,
          state: "error",
          label: "--",
          lines: ["no usable coding-quota windows"],
        }
      else
        ($ranked | min_by(.pct)) as $best
        | (100 - $best.pct
          | if . < 0 then 0 elif . > 100 then 100 else . end) as $remaining
        | (if $remaining <= 20 then "critical"
          elif $remaining <= 50 then "warning"
          else "ok"
          end) as $state
        | {
            present: true,
            state: $state,
            remaining: $remaining,
            label: (
              ($best.label | tag)
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
          }
      end
  end
