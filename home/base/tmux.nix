# Tmux configuration
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    prefix = "C-b";
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    historyLimit = 50000;
    mouse = true;
    keyMode = "vi";
    terminal = "screen-256color";

    extraConfig = ''
      set-option -g default-command "${pkgs.fish}/bin/fish -l"

      bind C-b send-prefix
      bind C-k clear-history
      bind -n M-g display-popup -d "#{pane_current_path}" -E "tmux new-session -A -s scratch"

      set -g renumber-windows on
      set-option -g focus-events on
      set -g set-clipboard on
      set -g status-position top
      set -g status-right-length 100
      set -g status-left-length 100
    '';

    plugins = with pkgs.tmuxPlugins; [
      sensible
      resurrect
      continuum
      copycat
      cpu
      {
        plugin = yank;
        extraConfig = "set -g @custom_copy_command 'true'";
      }
      {
        plugin = catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor 'mocha'
          set -g @catppuccin_window_status_style 'rounded'
          set -g @catppuccin_window_number_position 'right'
          set -g @catppuccin_window_status 'no'
          set -g @catppuccin_window_text '#W'
          set -g @catppuccin_window_current_fill 'number'
          set -g @catppuccin_window_current_text '#W'
          set -g @catppuccin_window_current_color '#{E:@thm_surface_2}'
          set -g @catppuccin_date_time_text '%d.%m. %H:%M'
          set -g @catppuccin_status_module_text_bg '#{E:@thm_mantle}'

          set -g status-left '#{E:@catppuccin_status_session}'
          set -gF status-right "#{E:@catppuccin_status_cpu}"
          set -agF status-right "#{@catppuccin_status_user}"
        '';
      }
    ];
  };
}
