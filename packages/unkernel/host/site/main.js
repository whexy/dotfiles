import { Terminal } from "./xterm/xterm.mjs";
import { FitAddon } from "./xterm/addon-fit.mjs";
import {
  checkSupport,
  createKernel,
  domButtonToLinux,
  domCodeToLinux,
  wispBackend,
} from "./unkernel/web.mjs";

const status = document.querySelector("#status");
const say = (text, kind = "") => {
  status.textContent = text;
  status.dataset.kind = kind;
};

const term = new Terminal({
  cursorBlink: true,
  fontFamily: getComputedStyle(document.body).fontFamily,
  fontSize: 14,
  theme: { background: "#16181d", foreground: "#d7dae0" },
});
const fit = new FitAddon();
term.loadAddon(fit);
term.open(document.querySelector("#terminal"));
fit.fit();

const screen = document.querySelector("#screen");
const canvas = screen.querySelector("canvas");

// The guest's picture, repainted once per animation frame while a program
// has the display open.
function showDisplay(vm) {
  const ctx = canvas.getContext("2d");
  let image = null;
  let seq = -1;
  let force = true;
  let raf = 0;
  const paint = () => {
    raf = requestAnimationFrame(paint);
    // A GL compositor's frame stays in the renderer's texture; null means
    // that the scanout is a plain buffer, which frame() reads.
    const drawn = vm.gl?.gpu?.drawFrame(ctx, force);
    if (drawn != null) {
      force = false;
      return;
    }
    force = true;
    if (vm.frameSeq !== undefined && vm.frameSeq === seq) {
      vm.requestFrame();
      return;
    }
    const frame = vm.frame(image.data);
    if (frame?.width === image.width && frame.height === image.height) {
      ctx.putImageData(image, 0, 0);
      seq = vm.frameSeq;
    }
  };
  return (mode) => {
    cancelAnimationFrame(raf);
    screen.hidden = !mode;
    fit.fit();
    if (!mode) return;
    canvas.width = mode.width;
    canvas.height = mode.height;
    image = new ImageData(mode.width, mode.height);
    seq = -1;
    force = true;
    raf = requestAnimationFrame(paint);
    canvas.focus();
  };
}

// Keys go to the guest's keyboard while the picture has the focus, and the
// pointer over the picture is the guest's tablet, an absolute pointer.
function sendInput(vm) {
  const ev = () => vm.evdev;
  // The host's niri binds are on Hyper, which kanata makes of a held
  // CapsLock on the real desktop; the guest has no kanata, and the browser
  // keeps Super for the operating system.
  const hyper = ["ControlLeft", "AltLeft", "ShiftLeft", "MetaLeft"];
  const key = (e) => {
    const down = e.type === "keydown";
    const codes = e.code === "CapsLock" ? hyper : [e.code];
    for (const code of codes) {
      const linux = domCodeToLinux(code);
      if (linux !== undefined) ev()?.key(linux, down);
    }
    e.preventDefault();
  };
  canvas.addEventListener("keydown", key);
  canvas.addEventListener("keyup", key);
  canvas.addEventListener("blur", () => ev()?.releaseAll());

  const aim = (e) => {
    const box = canvas.getBoundingClientRect();
    ev()?.moveTo(
      Math.min(1, Math.max(0, (e.clientX - box.left) / box.width)),
      Math.min(1, Math.max(0, (e.clientY - box.top) / box.height)),
    );
  };
  const button = (e) => {
    aim(e);
    const down = e.type === "pointerdown";
    if (down) {
      canvas.focus();
      canvas.setPointerCapture(e.pointerId);
    }
    const linux = domButtonToLinux(e.button);
    if (linux !== undefined) ev()?.tabletButton(linux, down);
    e.preventDefault();
  };
  canvas.addEventListener("pointermove", aim);
  canvas.addEventListener("pointerdown", button);
  canvas.addEventListener("pointerup", button);
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  canvas.addEventListener(
    "wheel",
    (e) => {
      if (e.deltaY) ev()?.tabletWheel(e.deltaY < 0 ? 1 : -1);
      e.preventDefault();
    },
    { passive: false },
  );
}

async function boot() {
  const support = await checkSupport();
  if (!support.ok) {
    say(
      `This browser cannot run the kernel:\n${support.problems.join("\n")}`,
      "error",
    );
    return;
  }

  const config = await (await fetch("config.json")).json();
  const params = new URLSearchParams(location.search);
  // Several CPUs need shared memory, which only an isolated page has.
  const isolated = globalThis.crossOriginIsolated === true;
  // Browsers open no sockets, so the guest's connections go through the Wisp
  // proxy the launcher runs beside this page, or the one ?wisp= names.
  const proxy = new URL(config.wisp, location.href);
  proxy.protocol = proxy.protocol === "https:" ? "wss:" : "ws:";
  const wisp = params.get("wisp") ?? proxy.href;

  let onDisplay = () => {};
  say("Starting the kernel");
  const vm = await createKernel({
    // The GPU has 3D only where the page gets WebGL2; elsewhere it is a
    // plain KMS device.
    ...(config.display
      ? {
          display: config.display,
          gpu: true,
          gl: true,
          onDisplay: (mode) => onDisplay(mode),
        }
      : {}),
    distro: new URL(config.image, location.href).href,
    cmdline: `console=hvc0 rdinit=/init kw.user=${config.user}`,
    memoryMiB: Number(params.get("mem")) || 1536,
    worker: isolated,
    cpus: isolated
      ? Number(params.get("cpus")) ||
        Math.min(4, navigator.hardwareConcurrency ?? 1)
      : 1,
    net: isolated
      ? { kind: "net", backend: { kind: "wisp", servers: wisp } }
      : wispBackend(wisp),
  });

  // From here the kernel's own log says where the boot is.
  say("");
  vm.onOutput((bytes) => term.write(bytes));
  term.onData((data) => vm.write(data));
  term.onResize(({ cols, rows }) => vm.resize(cols, rows));
  new ResizeObserver(() => fit.fit()).observe(
    document.querySelector("#terminal"),
  );
  vm.resize(term.cols, term.rows);
  term.focus();
  if (config.display) {
    onDisplay = showDisplay(vm);
    sendInput(vm);
  }

  const { kind, code } = await vm.exited;
  say(`The machine stopped (${kind}, code ${code}). Reload to boot it again.`);
}

boot().catch((error) => say(String(error?.message ?? error), "error"));
