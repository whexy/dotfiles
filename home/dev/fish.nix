# Shell configuration (fish, fzf, direnv, etc.)
{ pkgs, lib, ... }:
{
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      batdiff
      batman
      batgrep
      batwatch
    ];
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
      "--header"
    ];
  };

  programs.starship =
    let
      getPreset =
        name:
        with builtins;
        removeAttrs (fromTOML (readFile "${pkgs.starship}/share/starship/presets/${name}.toml")) [
          "\"$schema\""
        ];
    in
    {
      enable = true;
      settings = lib.recursiveUpdate (lib.mergeAttrsList [
        (getPreset "nerd-font-symbols")
        (getPreset "pure-preset")
      ]) { };
    };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fish = {
    enable = true;

    shellAliases = {
      venv = "source .venv/bin/activate.fish";
      op-signin = "eval (${pkgs._1password-cli}/bin/op signin)";
    };

    shellInit = ''
      # Pin ssh socket to a fixed path
      # so tmux & zellij sessions can always get new sock without restart
      if test -n "$SSH_AUTH_SOCK"; and string match -q "/tmp/*" "$SSH_AUTH_SOCK"
        ln -sf "$SSH_AUTH_SOCK" $HOME/.ssh/ssh-agent.sock
        set -gx SSH_AUTH_SOCK "$HOME/.ssh/ssh-agent.sock"
      end
    '';

    interactiveShellInit = ''
      # Devbox completion
      if command -v devbox &>/dev/null
        devbox completion fish | source
      end

      # Fix fzf.fish keybindings if installed
      if test -n "$FZF_DEFAULT_OPTS"
        set -gx FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS --height=15 --reverse"
      end

      # Docker abbreviations (commonly used)
      abbr -a d docker
      abbr -a dps 'docker ps'
      abbr -a dpsa 'docker ps -a'
      abbr -a di 'docker images'
      abbr -a dex 'docker exec -it'
      abbr -a dlog 'docker logs'
      abbr -a dlogf 'docker logs -f'
      abbr -a dstop 'docker stop'
      abbr -a drm 'docker rm'
      abbr -a drmi 'docker rmi'
      abbr -a db 'docker build'
      abbr -a dbu 'docker build -t'
      abbr -a dr 'docker run'
      abbr -a drit 'docker run -it'
      abbr -a dc 'docker compose'
      abbr -a dcu 'docker compose up'
      abbr -a dcud 'docker compose up -d'
      abbr -a dcd 'docker compose down'
      abbr -a dcl 'docker compose logs'
      abbr -a dclf 'docker compose logs -f'
      abbr -a dcps 'docker compose ps'
      abbr -a dce 'docker compose exec'

      # Tmux abbreviations (commonly used)
      abbr -a ta 'tmux attach -t'
      abbr -a tad 'tmux attach -d -t'
      abbr -a ts 'tmux new-session -s'
      abbr -a tl 'tmux list-sessions'
      abbr -a tkss 'tmux kill-session -t'
      abbr -a tksv 'tmux kill-server'
    '';

    functions = {
      # Path context-aware directory jump using fzf
      pd = ''
        set -l selected (
          dirs -v | while read -l idx dir
            # Expand tilde and resolve path
            set -l expanded_dir (string replace -r '^~' $HOME $dir)
            if test -d "$expanded_dir"
              realpath "$expanded_dir" 2>/dev/null
            end
          end | fzf --height=15 --reverse --prompt="dir> " --preview 'eza -1 -hl --icons --color=always {}'
        )

        if test -n "$selected"
          cd "$selected"
        end
      '';

      # Fish equivalent of oh-my-zsh extract plugin
      extract = ''
        if test (count $argv) -eq 0
          echo "Usage: extract <file>"
          return 1
        end

        set -l file $argv[1]
        if not test -f "$file"
          echo "Error: '$file' is not a valid file"
          return 1
        end

        switch $file
          case '*.tar.bz2' '*.tbz2'
            tar xjf "$file"
          case '*.tar.gz' '*.tgz'
            tar xzf "$file"
          case '*.tar.xz' '*.txz'
            tar xJf "$file"
          case '*.tar'
            tar xf "$file"
          case '*.bz2'
            bunzip2 "$file"
          case '*.gz'
            gunzip "$file"
          case '*.zip'
            unzip "$file"
          case '*.Z'
            uncompress "$file"
          case '*.rar'
            unrar x "$file"
          case '*.7z'
            7z x "$file"
          case '*'
            echo "Error: '$file' cannot be extracted via extract"
            return 1
        end
      '';

      # Fish has a built-in way to handle "sudo last command"
      # This mimics oh-my-zsh sudo plugin behavior
      sudo-last = ''
        set -l last_cmd (history --max=1)
        if test -n "$last_cmd"
          commandline -r "sudo $last_cmd"
          commandline -f execute
        end
      '';
    };

    # Fish plugins using Home Manager
    plugins = [
      # fzf.fish - Better fzf integration for Fish
      {
        name = "fzf.fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      # Puffer Fish - Expand !! and !$ like in Zsh
      {
        name = "puffer-fish";
        src = pkgs.fishPlugins.puffer.src;
      }
      # Git abbreviations - oh-my-zsh style git aliases
      {
        name = "plugin-git";
        src = pkgs.fishPlugins.plugin-git.src;
      }
      # Kubectl abbreviations - from lewisacidic/fish-kubectl-abbr
      {
        name = "fish-kubectl-abbr";
        src = pkgs.fetchFromGitHub {
          owner = "lewisacidic";
          repo = "fish-kubectl-abbr";
          rev = "161450ab83da756c400459f4ba8e8861770d930c";
          sha256 = "sha256-iKNaD0E7IwiQZ+7pTrbPtrUcCJiTcVpb9ksVid1J6A0=";
        };
      }
    ];
  };
}
