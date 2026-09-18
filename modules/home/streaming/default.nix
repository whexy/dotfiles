{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.streaming;
in
{
  options.dotfiles.streaming.enable = lib.mkEnableOption "streaming";

  config = lib.mkIf cfg.enable (
    let
      countdown = pkgs.writeShellApplication {
        name = "countdown";
        runtimeInputs = with pkgs; [
          cowsay
          coreutils
          ncurses
          gawk
        ];
        text = ''
          seconds=30
          template="streaming in %t..."

          while getopts "t:" opt; do
            case $opt in
              t) seconds="$OPTARG" ;;
              *) echo "Usage: countdown [-t seconds] [message with %t]" >&2; exit 1 ;;
            esac
          done
          shift $((OPTIND - 1))
          if [ $# -ge 1 ]; then
            template="$1"
          fi

          for i in $(seq "$seconds" -1 0); do
            clear
            msg="$(cowsay -f sus "''${template//%t/$i}")"
            rows=$(tput lines)
            cols=$(tput cols)
            h=$(echo "$msg" | wc -l)
            w=$(echo "$msg" | awk '{print length}' | sort -nr | head -1)
            top_padding=$(( (rows - h) / 2 ))
            left_padding=$(( (cols - w) / 2 ))
            printf "\n%.0s" $(seq 1 "$top_padding")
            echo "$msg" | while IFS= read -r line; do
              printf "%*s%s\n" "$left_padding" "" "$line"
            done
            [ "$i" -eq 0 ] || sleep 1
          done
          clear
        '';
      };
    in
    {
      home.packages = [ countdown ];
    }
  );
}
