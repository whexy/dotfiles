export type Cap = "base" | "dev" | "dev-lite" | "gui" | "service";

export interface Host {
  /** Display name (flake target where applicable). */
  label: string;
  /** Hardware / role note shown on fleet cards. */
  hardware: string;
  /** Capability badges. */
  caps: Cap[];
  /** Command shown in the builder. */
  cmd: string;
  /** nh variant, if applicable. */
  nhCmd?: string;
  /** One-liner rendered under the command. */
  note: string;
}

export interface Category {
  key: string;
  label: string;
  hosts: Host[];
}

export const categories: Category[] = [
  {
    key: "nixos",
    label: "NixOS",
    hosts: [
      {
        label: "ord",
        hardware: "Ryzen 5800X · home workstation",
        caps: ["base", "dev", "gui"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#ord",
        nhCmd: "nh os switch --hostname ord github:whexy/dotfiles",
        note: "Home workstation. The daily driver.",
      },
      {
        label: "remote-dev",
        hardware: "Threadripper 9995WX · lab VM on b3srv0",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#remote-dev",
        nhCmd: "nh os switch --hostname remote-dev github:whexy/dotfiles",
        note: "Lab development VM with silly amounts of compute.",
      },
      {
        label: "mvp",
        hardware: "Ryzen 5700X · lab workstation VM",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#mvp",
        nhCmd: "nh os switch --hostname mvp github:whexy/dotfiles",
        note: "Lab workstation VM.",
      },
      {
        label: "mba-nixos",
        hardware: "Apple M5 MacBook Air · NixOS",
        caps: ["base", "dev", "gui"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#mba-nixos",
        nhCmd: "nh os switch --hostname mba-nixos github:whexy/dotfiles",
        note: "Apple silicon, no macOS. Full NixOS on the M5 Air.",
      },
      {
        label: "remote-basic",
        hardware: "generic remote host",
        caps: ["base"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#remote-basic",
        nhCmd: "nh os switch --hostname remote-basic github:whexy/dotfiles",
        note: "Minimal generic remote host.",
      },
    ],
  },
  {
    key: "macos",
    label: "macOS",
    hosts: [
      {
        label: "mba",
        hardware: "MacBook Air",
        caps: ["base", "dev-lite", "gui"],
        cmd: "sudo darwin-rebuild switch --flake github:whexy/dotfiles#mba",
        nhCmd: "nh darwin switch --hostname mba github:whexy/dotfiles",
        note: "MacBook Air via nix-darwin.",
      },
      {
        label: "mini",
        hardware: "Mac Mini",
        caps: ["base", "dev-lite", "gui"],
        cmd: "sudo darwin-rebuild switch --flake github:whexy/dotfiles#mini",
        nhCmd: "nh darwin switch --hostname mini github:whexy/dotfiles",
        note: "Mac Mini desktop via nix-darwin.",
      },
    ],
  },
  {
    key: "home",
    label: "Home Manager",
    hosts: [
      {
        label: "venus",
        hardware: "wenxuan @ /home/wenxuan",
        caps: ["base", "dev"],
        cmd: "home-manager switch --flake github:whexy/dotfiles#wenxuan@venus",
        nhCmd:
          "nh home switch github:whexy/dotfiles --no-nom -c wenxuan@venus -b backup",
        note: "Standalone Home Manager on venus.",
      },
      {
        label: "mars",
        hardware: "wenxuan @ /data/wenxuan",
        caps: ["base", "dev"],
        cmd: "home-manager switch --flake github:whexy/dotfiles#wenxuan@mars",
        nhCmd:
          "nh home switch github:whexy/dotfiles --no-nom -c wenxuan@mars -b backup",
        note: "Standalone Home Manager on mars.",
      },
    ],
  },
  {
    key: "images",
    label: "Images",
    hosts: [
      {
        label: "WSL tarball",
        hardware: "NixOS-WSL importable tarball",
        caps: ["base", "dev"],
        cmd: "just build-wsl",
        note: "Import with: wsl --import NixOS <path> result/wsl/nixos.wsl",
      },
      {
        label: "Proxmox · remote-service",
        hardware: "Proxmox VMA image",
        caps: ["base", "service"],
        cmd: "just build-proxmox remote-service",
        note: "Headless service host. qmrestore <file>.vma.zst <vmid>.",
      },
      {
        label: "moore VM",
        hardware: "QEMU dev VM launcher",
        caps: ["base", "dev"],
        cmd: "just build-moore-vm",
        note: "Dev VM for the moore server. ssh -p 2222 whexy@localhost.",
      },
      {
        label: "UTM · x86_64",
        hardware: "qcow2 desktop image",
        caps: ["base", "dev", "gui"],
        cmd: "just build-desktop utm x86_64",
        note: "Import into UTM as the main disk, boot UEFI.",
      },
      {
        label: "UTM · aarch64",
        hardware: "qcow2 desktop image",
        caps: ["base", "dev", "gui"],
        cmd: "just build-desktop utm aarch64",
        note: "Import into UTM as the main disk, boot UEFI.",
      },
      {
        label: "VMware · x86_64",
        hardware: "VMDK desktop image",
        caps: ["base", "dev", "gui"],
        cmd: "just build-desktop vmware x86_64",
        note: "Attach the VMDK as the disk of a new VM.",
      },
      {
        label: "VMware · aarch64",
        hardware: "VMDK desktop image",
        caps: ["base", "dev", "gui"],
        cmd: "just build-desktop vmware aarch64",
        note: "Attach the VMDK as the disk of a new VM.",
      },
    ],
  },
];

export const capNotes: Record<Cap, { name: string; blurb: string }> = {
  base: {
    name: "base",
    blurb:
      "The floor every machine stands on. zsh, tmux, neovim, btop — nothing more, nothing less.",
  },
  dev: {
    name: "dev",
    blurb:
      "The full development environment. Fancy NeoVim, LSPs, linters, formatters, direnv, agents.",
  },
  "dev-lite": {
    name: "dev-lite",
    blurb: "Development, trimmed for macOS. The essentials without the weight.",
  },
  gui: {
    name: "gui",
    blurb:
      "Desktop environments. ghostty, firefox, niri, fonts — plus dock, finder and Touch ID on macOS.",
  },
  service: {
    name: "service",
    blurb: "Headless service hosts. Minimal, hardened, always on.",
  },
};

export const stack: { name: string; note: string }[] = [
  { name: "neovim", note: "editor, heavily configured" },
  { name: "zellij", note: "terminal multiplexer" },
  { name: "tmux", note: "the other multiplexer" },
  { name: "zsh", note: "shell" },
  { name: "ghostty", note: "terminal emulator" },
  { name: "niri", note: "scrollable-tiling wayland compositor" },
  { name: "waybar", note: "status bar" },
  { name: "aerospace", note: "tiling wm for macOS" },
  { name: "karabiner", note: "keyboard remapping" },
  { name: "firefox", note: "browser, policies included" },
  { name: "agenix", note: "age-encrypted secrets" },
  { name: "disko", note: "declarative disk partitioning" },
  { name: "blueprint", note: "flake structure, zero boilerplate" },
  { name: "treefmt", note: "one formatter to rule them all" },
  { name: "nix-index-database", note: "comma for everything" },
  { name: "llm-agents", note: "opencode & claude-code, pinned" },
];

/** Commands cycled through in the hero terminal. */
export const heroCommands: string[] = [
  "sudo nixos-rebuild switch --flake github:whexy/dotfiles#ord",
  "sudo darwin-rebuild switch --flake github:whexy/dotfiles#mba",
  "home-manager switch --flake github:whexy/dotfiles#wenxuan@mars",
  "just build-desktop utm aarch64",
];
