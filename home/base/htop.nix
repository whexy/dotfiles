# Htop configuration
{ config, ... }:
{
  programs.htop = {
    enable = true;
    settings = {
      fields = with config.lib.htop.fields; [
        PID
        USER
        PRIORITY
        NICE
        M_SIZE
        M_RESIDENT
        M_SHARE
        STATE
        PERCENT_CPU
        PERCENT_MEM
        TIME
        IO_RATE
        COMM
      ];
      hide_kernel_threads = 1;
      hide_userland_threads = 0;
      shadow_other_users = 0;
      show_thread_names = 1;
      show_program_path = 0;
      highlight_base_name = 1;
      highlight_deleted_exe = 1;
      highlight_megabytes = 1;
      highlight_threads = 1;
      highlight_changes = 1;
      highlight_changes_delay_secs = 3;
      color_scheme = 6;
      enable_mouse = 1;
      delay = 10;
      header_layout = "two_50_50";
      tree_view = 0;
      sort_key = 46;
      sort_direction = -1;
    }
    // (
      with config.lib.htop;
      leftMeters [
        (bar "CPU")
        (bar "Memory")
        (text "DiskIO")
        (text "NetworkIO")
      ]
    )
    // (
      with config.lib.htop;
      rightMeters [
        (text "Tasks")
        (text "LoadAverage")
        (text "Uptime")
        (text "Systemd")
      ]
    );
  };
}
