{
  imports = [
    ./base.nix

    ./dev/agents.nix
    ./dev/git.nix
    ./dev/shell.nix
    ./dev/ssh.nix
    ./dev/neovim.nix
  ];

  home-manager.users.whexy =
    { pkgs, ... }:
    {
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
      };

      home.packages = with pkgs; [
        # Quick tool
        uv
        xh

        tree-sitter
        # Formatters & Linters
        black
        golangci-lint
        nixfmt-rfc-style
        rustfmt
        shellcheck
        shfmt
        stylua
        typstyle
        yamlfmt

        # LSP
        basedpyright
        clang-tools
        gopls
        lua-language-server
        nil
        ruff
        tinymist
        tombi
        typescript-language-server
        vscode-langservers-extracted
        yaml-language-server
      ];

    };
}
