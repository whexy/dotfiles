# The launcher of an unkernel host: serves the page that boots its image in a
# browser tab, or boots the image in this terminal. It takes the packages of
# the machine that runs it, not of the host inside the image.
{
  pkgs,
  unkernel,
  wisp-server,
  system,
}:
let
  inherit (pkgs) lib;
  inherit (system.networking) hostName;
  user = system.dotfiles.host.username;

  image = import ./image.nix {
    inherit pkgs;
    inherit (system.system.build) toplevel;
  };

  xterm = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz";
    hash = "sha256-zvXw/gCBNx2oHI7qQTVrFJs4ulvNdduRgk+c+RIgsoE=";
  };
  xtermFit = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz";
    hash = "sha256-W7UvELD7qWafLVdLSCK8/ijEgf8eltSqIf4u2ze8fhM=";
  };

  # The image's name carries its hash, so a browser never reads a cached
  # range of an older image.
  imageName = "${lib.substring 11 32 image.outPath}.erofs";

  site = pkgs.runCommand "${hostName}-site" { } ''
    mkdir -p $out/xterm
    cp ${./site}/* $out/
    cp ${xterm}/lib/xterm.mjs ${xterm}/css/xterm.css ${xtermFit}/lib/addon-fit.mjs $out/xterm/
    ln -s ${unkernel.web} $out/unkernel
    ln -s ${image} $out/${imageName}
    cp ${
      pkgs.writeText "config.json" (
        builtins.toJSON {
          image = imageName;
          wisp = "wisp/";
          inherit hostName user;
          display =
            let
              inherit (system.dotfiles.platform.unkernel) display;
            in
            if display.enable then { inherit (display) width height; } else null;
        }
      )
    } $out/config.json
  '';

  # Range requests read the image lazily, and the isolation headers give the
  # page the shared memory that several CPUs need.
  #
  # /wisp/ opens TCP and UDP connections from this machine for whoever reaches
  # it. A WebSocket is not bound by the same-origin policy, so any site open
  # in a browser on this machine could connect to it; the Origin check admits
  # only this page.
  caddyfile = pkgs.writeText "Caddyfile" ''
    {
    	admin off
    	auto_https off
    }
    http://:{$UNKERNEL_PORT} {
    	bind {$UNKERNEL_HOST}
    	header {
    		Cross-Origin-Opener-Policy same-origin
    		Cross-Origin-Embedder-Policy require-corp
    		Cross-Origin-Resource-Policy same-origin
    	}
    	@wisp {
    		path /wisp/
    		import {$UNKERNEL_ORIGINS}
    	}
    	handle @wisp {
    		reverse_proxy 127.0.0.1:{$UNKERNEL_WISP_PORT}
    	}
    	handle /wisp/* {
    		respond 403
    	}
    	handle {
    		root * ${site}
    		file_server
    	}
    }
  '';
in
pkgs.writeShellApplication {
  name = hostName;
  runtimeInputs = [
    pkgs.caddy
    pkgs.python3
    pkgs.util-linux
    unkernel
    wisp-server
  ];
  text = ''
    case ''${1:-serve} in
    serve)
      listen=''${2:-127.0.0.1:8377}
      export UNKERNEL_HOST=''${listen%:*} UNKERNEL_PORT=''${listen##*:}
      # The origins the page is opened at: the listen address, and any others
      # named after it, such as an HTTPS name in front of this server.
      UNKERNEL_ORIGINS=$(mktemp)
      printf 'header Origin %s\n' "http://$listen" "http://localhost:$UNKERNEL_PORT" "''${@:3}" >"$UNKERNEL_ORIGINS"
      UNKERNEL_WISP_PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
      export UNKERNEL_ORIGINS UNKERNEL_WISP_PORT

      # The proxy refuses loopback and private destinations.
      # It serves from a child process, so it gets a process group to stop.
      setsid wisp-server --host 127.0.0.1 --port "$UNKERNEL_WISP_PORT" --threads 1 \
        --dns-order ipv4first --log-level warning &
      wisp=$!
      caddy run --adapter caddyfile --config ${caddyfile} &
      trap 'kill -- -$wisp $! 2>/dev/null; rm -f "$UNKERNEL_ORIGINS"' EXIT

      echo "${hostName}: http://$listen/"
      wait -n
      ;;
    console)
      shift
      exec unkernel --distro ${image} --user ${user} --cpus 4 "$@"
      ;;
    *)
      echo "usage: ${hostName} [serve [ADDRESS:PORT [ORIGIN...]] | console [UNKERNEL OPTIONS]]" >&2
      exit 2
      ;;
    esac
  '';
  derivationArgs.passthru = { inherit image site; };
}
