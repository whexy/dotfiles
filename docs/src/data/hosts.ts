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
        label: "ellison",
        hardware: "home workstation",
        caps: ["base", "dev", "gui"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#ellison",
        nhCmd: "nh os switch --hostname ellison github:whexy/dotfiles",
        note: "Home workstation. The daily driver. Gaming included.",
      },
      {
        label: "mudd",
        hardware: "lab VM",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#mudd",
        nhCmd: "nh os switch --hostname mudd github:whexy/dotfiles",
        note: "Lab development VM. Auto-upgrading.",
      },
      {
        label: "zoozve",
        hardware: "Incus VM",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#zoozve",
        nhCmd: "nh os switch --hostname zoozve github:whexy/dotfiles",
        note: "Incus development VM with an encrypted root disk and guest agent.",
      },
      {
        label: "phobos",
        hardware: "Incus VM",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#phobos",
        nhCmd: "nh os switch --hostname phobos github:whexy/dotfiles",
        note: "Incus VM with LUKS-encrypted root and guest agent. Auto-upgrading.",
      },
      {
        label: "neith",
        hardware: "Incus container",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#neith",
        nhCmd: "nh os switch --hostname neith github:whexy/dotfiles",
        note: "Incus system container for development. Auto-upgrading.",
      },
      {
        label: "skokie",
        hardware: "Apple silicon desktop VM",
        caps: ["base", "dev", "gui"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#skokie",
        nhCmd: "nh os switch --hostname skokie github:whexy/dotfiles",
        note: "VMware desktop VM running on a MacBook. Image: just build-desktop.",
      },
      {
        label: "wsl",
        hardware: "NixOS-WSL",
        caps: ["base", "dev"],
        cmd: "sudo nixos-rebuild switch --flake github:whexy/dotfiles#wsl",
        nhCmd: "nh os switch --hostname wsl github:whexy/dotfiles",
        note: "NixOS under WSL on Windows. Import with just build-wsl.",
      },
    ],
  },
  {
    key: "macos",
    label: "macOS",
    hosts: [
      {
        label: "golf",
        hardware: "MacBook Air",
        caps: ["base", "dev", "gui"],
        cmd: "sudo darwin-rebuild switch --flake github:whexy/dotfiles#golf",
        nhCmd: "nh darwin switch --hostname golf github:whexy/dotfiles",
        note: "MacBook Air via nix-darwin.",
      },
      {
        label: "sheridan",
        hardware: "Mac Mini",
        caps: ["base", "dev-lite", "gui"],
        cmd: "sudo darwin-rebuild switch --flake github:whexy/dotfiles#sheridan",
        nhCmd: "nh darwin switch --hostname sheridan github:whexy/dotfiles",
        note: "Mac Mini desktop via nix-darwin. Never sleeps.",
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
      {
        label: "b3srv0",
        hardware: "root @ /root",
        caps: ["base"],
        cmd: "home-manager switch --flake github:whexy/dotfiles#root@b3srv0",
        nhCmd:
          "nh home switch github:whexy/dotfiles --no-nom -c root@b3srv0 -b backup",
        note: "Root profile on the b3srv0 server, with AI agents. Auto-upgrading.",
      },
      {
        label: "proxmox",
        hardware: "root @ /root",
        caps: ["base"],
        cmd: "home-manager switch --flake github:whexy/dotfiles#root@proxmox",
        nhCmd:
          "nh home switch github:whexy/dotfiles --no-nom -c root@proxmox -b backup",
        note: "Root profile on the Proxmox host, with AI agents. Auto-upgrading.",
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
        label: "desktop VM",
        hardware: "VMDK desktop image",
        caps: ["base", "dev", "gui"],
        cmd: "just build-desktop",
        note: "Attach the VMDK as the disk of a new VMware VM.",
      },
      {
        label: "moore VM",
        hardware: "QEMU dev VM launcher",
        caps: ["base", "dev"],
        cmd: "just build-moore-vm",
        note: "Dev VM for the moore server. ssh -p 2222 whexy@localhost.",
      },
      {
        label: "zoozve image",
        hardware: "Encrypted Incus image",
        caps: ["base", "dev"],
        cmd: "just build-zoozve",
        note: "LUKS-encrypted qcow2 + Incus metadata. Import with incus image import.",
      },
      {
        label: "phobos image",
        hardware: "Encrypted Incus image",
        caps: ["base", "dev"],
        cmd: "just build-phobos",
        note: "LUKS-encrypted qcow2 + Incus metadata. Import with incus image import.",
      },
      {
        label: "neith image",
        hardware: "Incus container image",
        caps: ["base", "dev"],
        cmd: "just build-neith",
        note: "Rootfs + Incus metadata tarballs. Import with incus image import.",
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
  { name: "sketchybar", note: "status bar for macOS" },
  { name: "aerospace", note: "tiling wm for macOS" },
  { name: "paneru", note: "tiling wm for macOS, experimental" },
  { name: "karabiner", note: "keyboard remapping" },
  { name: "firefox", note: "browser, policies included" },
  { name: "beszel", note: "fleet monitoring" },
  { name: "agenix", note: "age-encrypted secrets" },
  { name: "disko", note: "declarative disk partitioning" },
  { name: "blueprint", note: "flake structure, zero boilerplate" },
  { name: "treefmt", note: "one formatter to rule them all" },
  { name: "nix-index-database", note: "comma for everything" },
  { name: "llm-agents", note: "opencode, claude-code & codex, pinned" },
];

/** Commands cycled through in the hero terminal. */
export const heroCommands: string[] = [
  "sudo nixos-rebuild switch --flake github:whexy/dotfiles#ellison",
  "sudo darwin-rebuild switch --flake github:whexy/dotfiles#golf",
  "home-manager switch --flake github:whexy/dotfiles#wenxuan@mars",
  "just build-desktop",
];
