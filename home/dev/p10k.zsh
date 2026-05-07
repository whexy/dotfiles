# Powerlevel10k configuration: Pure style with nix-shell awareness.
# Managed by Nix -- do not edit manually.
#
# Based on p10k's built-in Pure preset with the following changes:
#   - Instant prompt set to 'quiet' (compatible with direnv, nix, etc.)
#   - Added nix_shell segment to show when inside a nix shell/devShell
#   - Transient prompt enabled (cleans up past prompts)

# Temporarily change options.
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  # Unset all configuration options.
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  # Zsh >= 5.1 is required.
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # Prompt colors.
  local grey=242
  local red=1
  local yellow=3
  local blue=4
  local magenta=5
  local cyan=6
  local white=7

  # Left prompt segments.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    context                   # user@host
    dir                       # current directory
    vcs                       # git status
    command_execution_time    # previous command duration
    # =========================[ Line #2 ]=========================
    newline                   # \n
    virtualenv                # python virtual environment
    nix_shell                 # nix shell indicator
    prompt_char               # prompt symbol
  )

  # Right prompt segments.
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    # =========================[ Line #2 ]=========================
    newline                   # \n
  )

  # Basic style options that define the overall prompt look.
  typeset -g POWERLEVEL9K_BACKGROUND=                            # transparent background
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=  # no surrounding whitespace
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '  # separate segments with a space
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=        # no end-of-line symbol
  typeset -g POWERLEVEL9K_VISUAL_IDENTIFIER_EXPANSION=           # no segment icons

  # Add an empty line before each prompt except the first.
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

  # Magenta prompt symbol if the last command succeeded.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS}_FOREGROUND=$magenta
  # Red prompt symbol if the last command failed.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS}_FOREGROUND=$red
  # Default prompt symbol.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  # Prompt symbol in command vi mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  # Prompt symbol in visual vi mode is the same as in command mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='❮'
  # Prompt symbol in overwrite vi mode is the same as in command mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=false

  # Grey Python Virtual Environment.
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$grey
  # Don't show Python version.
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false
  typeset -g POWERLEVEL9K_VIRTUALENV_{LEFT,RIGHT}_DELIMITER=

  # Cyan nix shell indicator.
  typeset -g POWERLEVEL9K_NIX_SHELL_FOREGROUND=$cyan

  # Blue current directory.
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$blue

  # Context format when root: user@host. The first part white, the rest grey.
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE="%F{$white}%n%f%F{$grey}@%m%f"
  # Context format when not root: user@host. The whole thing grey.
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE="%F{$grey}%n@%m%f"
  # Don't show context unless root or in SSH.
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_CONTENT_EXPANSION=

  # Show previous command duration only if it's >= 5s.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=5
  # Don't show fractional seconds. Thus, 7s rather than 7.3s.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  # Duration format: 1d 2h 3m 4s.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
  # Yellow previous command duration.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$yellow

  # Grey Git prompt. This makes stale prompts indistinguishable from up-to-date ones.
  typeset -g POWERLEVEL9K_VCS_FOREGROUND=$grey

  # Disable async loading indicator to make directories that aren't Git repositories
  # indistinguishable from large Git repositories without known state.
  typeset -g POWERLEVEL9K_VCS_LOADING_TEXT=

  # Don't wait for Git status even for a millisecond, so that prompt always updates
  # asynchronously when Git state changes.
  typeset -g POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS=0

  # Cyan ahead/behind arrows.
  typeset -g POWERLEVEL9K_VCS_{INCOMING,OUTGOING}_CHANGESFORMAT_FOREGROUND=$cyan
  # Don't show remote branch, current tag or stashes.
  typeset -g POWERLEVEL9K_VCS_GIT_HOOKS=(vcs-detect-changes git-untracked git-aheadbehind)
  # Don't show the branch icon.
  typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=
  # When in detached HEAD state, show @commit where branch normally goes.
  typeset -g POWERLEVEL9K_VCS_COMMIT_ICON='@'
  # Don't show staged, unstaged, untracked indicators.
  typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED}_ICON=
  # Show '*' when there are staged, unstaged or untracked files.
  typeset -g POWERLEVEL9K_VCS_DIRTY_ICON='*'
  # Show '⇣' if local branch is behind remote.
  typeset -g POWERLEVEL9K_VCS_INCOMING_CHANGES_ICON=':⇣'
  # Show '⇡' if local branch is ahead of remote.
  typeset -g POWERLEVEL9K_VCS_OUTGOING_CHANGES_ICON=':⇡'
  # Don't show the number of commits next to the ahead/behind arrows.
  typeset -g POWERLEVEL9K_VCS_{COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=1
  # Remove space between '⇣' and '⇡' and all trailing spaces.
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${${${P9K_CONTENT/⇣* :⇡/⇣⇡}// }//:/ }'

  # Transient prompt: trim previous prompts to just the prompt symbol.
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always

  # Instant prompt mode.
  #   - quiet:   Enable instant prompt, suppress warnings about console output during init.
  #              Safe with direnv (silent=true), nix-direnv, and similar tools.
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

  # Disable hot reload for faster prompt rendering.
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # If p10k is already loaded, reload configuration.
  # This works even with POWERLEVEL9K_DISABLE_HOT_RELOAD=true.
  (( ! $+functions[p10k] )) || p10k reload
}

# Tell `p10k configure` which file it should overwrite.
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
