# Model-checks iPhone Use's live preview (PreviewStream.tla) with TLC, for
# each pauser on this host. StallTimeout comes from the curl command the
# packaged server runs, and the check fails when iphone-use-select and the
# patched server name the relay variable differently. The `.agents/skills/
# verify-iphone-preview` skill says what the model covers.
{ pkgs, perSystem, ... }:
let
  server = "${perSystem.self.iphone-use}/share/iphone-use/server/wda_screen.py";
  selector = ../../packages/iphone-wda/iphone_use_select.py;
in
pkgs.runCommand "iphone-preview"
  {
    nativeBuildInputs = [
      pkgs.tlaplus
      pkgs.gnugrep
    ];
  }
  ''
    for file in ${server} ${selector}; do
      grep -q IPHONE_USE_MJPEG_URL "$file" || {
        echo "$file does not name IPHONE_USE_MJPEG_URL" >&2
        exit 1
      }
    done
    if grep -q '"--speed-limit"' ${server}; then timeout=TRUE; else timeout=FALSE; fi
    echo "StallTimeout = $timeout"

    cp ${./PreviewStream.tla} PreviewStream.tla
    for pauser in reader worker process; do
      sed "s/StallTimeout = TRUE/StallTimeout = $timeout/" ${./.}/Preview-$pauser.cfg > $pauser.cfg
      echo "== Pauser = $pauser"
      tlc -workers auto -metadir meta-$pauser -config $pauser.cfg PreviewStream.tla > $pauser.log 2>&1 || true
      if ! grep -q "No error has been found" $pauser.log; then
        cat $pauser.log
        exit 1
      fi
      grep "distinct states found, 0 states left" $pauser.log | tail -1
    done
    touch $out
  ''
