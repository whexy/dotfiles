import { FitAddon, Terminal, init } from "./ghostty-web/ghostty-web.js";
import { checkSupport, createKernel, wispBackend } from "./unkernel/web.mjs";
import { attachWayland } from "./wayland.js";

const $ = (selector) => document.querySelector(selector);

function icon(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "icon");
  svg.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", `#i-${name}`);
  svg.append(use);
  return svg;
}

const status = $("#status");
let statusText = "";
function say(text) {
  statusText = text;
  status.textContent = text;
  status.hidden = !text;
}
status.addEventListener("click", () => say(""));

const elapsed = (ms) =>
  ms < 1000 ? `${Math.round(ms)} ms` : `${(ms / 1000).toFixed(1)} s`;
const mebibytes = (bytes) => `${(bytes / 1048576).toFixed(1)} MiB`;

// ================= Boot milestones =================

const startedAt = performance.now();
const bootSummary = $("#boot-summary");
const bootSteps = $("#boot-steps");
const bootClock = $("#boot-clock");
const bootMeter = $("#boot-meter");
const hostState = $("#host-state");
// Milestones a successful boot completes; the meter counts them.
const bootMilestones = 9;
let doneSteps = 0;
let stepFraction = 0;
let pendingStep = bootSteps.lastElementChild;

const clock = setInterval(() => {
  bootClock.textContent = elapsed(performance.now() - startedAt);
}, 100);

function meter() {
  const progress = Math.min(1, (doneSteps + stepFraction) / bootMilestones);
  bootMeter.style.setProperty("--progress", progress.toFixed(3));
}

function bootStep(label, { pending = false, detail = "", fraction = 0 } = {}) {
  const step =
    pendingStep ?? bootSteps.appendChild(document.createElement("li"));
  const text = document.createElement("span");
  text.className = "step-label";
  text.textContent = label;
  if (detail) {
    const small = document.createElement("small");
    small.textContent = ` · ${detail}`;
    text.append(small);
  }
  const mark = pending ? document.createElement("span") : icon("check");
  if (pending) mark.className = "spinner";
  const time = document.createElement("span");
  time.className = "step-time";
  if (!pending) time.textContent = elapsed(performance.now() - startedAt);
  step.replaceChildren(mark, text, time);
  step.toggleAttribute("data-pending", pending);
  pendingStep = pending ? step : null;
  if (!pending) doneSteps += 1;
  stepFraction = pending ? fraction : 0;
  meter();
}

function reportBoot(progress) {
  switch (progress.stage) {
    case "compile":
      bootStep("Preparing the WebAssembly kernel", { pending: true });
      break;
    case "download": {
      const asset = progress.what === "kernel" ? "kernel" : "initramfs";
      const size = mebibytes(progress.loaded);
      if (progress.done) {
        bootStep(`Downloaded the ${asset}`, { detail: size });
      } else {
        const total = progress.total ? ` of ${mebibytes(progress.total)}` : "";
        bootStep(`Downloading the ${asset}`, {
          pending: true,
          detail: `${size}${total}`,
          fraction: progress.total ? progress.loaded / progress.total : 0,
        });
      }
      break;
    }
    case "compiled":
      bootStep("Compiled the kernel", { detail: elapsed(progress.ms) });
      bootStep("Opening the NixOS image", { pending: true });
      break;
    case "memory":
      bootStep("Opened the NixOS image");
      bootStep("Allocated guest memory", { detail: `${progress.mib} MiB` });
      break;
    case "instantiate":
      bootStep("Starting Linux", { pending: true });
      break;
    case "start":
      bootStep("Started Linux");
      bootStep("Waiting for NixOS init", { pending: true });
      break;
  }
}

function bootFailed(message) {
  clearInterval(clock);
  bootSummary.textContent = "NixOS could not start";
  pendingStep?.remove();
  pendingStep = null;
  hostState.textContent = "Stopped";
  const error = $("#boot-error");
  error.textContent = message;
  error.hidden = false;
  if (startup.hidden) say(message);
}

// ================= Preferences =================

const params = new URLSearchParams(location.search);
const isolated = globalThis.crossOriginIsolated === true;
const settings = $("#settings");
const preferences = $("#preferences");
const fields = preferences.elements;
const fontSizeField = $("#font-size");
let saved = {};
try {
  const stored = JSON.parse(localStorage.getItem("tab-preferences"));
  if (stored && typeof stored === "object") saved = stored;
} catch {
  // Storage can be blocked by the browser.
}
function savePreferences(values) {
  Object.assign(saved, values);
  try {
    localStorage.setItem("tab-preferences", JSON.stringify(saved));
  } catch {
    // The current page can still use the selected values.
  }
}
const cpus = isolated
  ? Number(params.get("cpus")) ||
    saved.cpus ||
    Math.min(4, navigator.hardwareConcurrency ?? 1)
  : 1;
const memory = Number(params.get("mem")) || saved.memory || 1536;
fields.cpus.value = cpus;
fields.cpus.disabled = !isolated;
fields.memory.value = memory;
fontSizeField.value = saved.fontSize ?? 14;

// ================= Tabs =================

const tabList = $("#tabs");
const consoleTab = $("#console-tab");
const workspace = $("#workspace");
const startup = $("#startup");
const consolePane = $("#console");
const newButton = $("#new-tab");
const menu = $("#new-tab-menu");
const tabs = new Map();
let activeTab = consoleTab;
let tabNumber = 0;
let shellNumber = 0;

function showConsole() {
  startup.hidden = true;
  consolePane.inert = false;
}

$("#view-console").addEventListener("click", () => {
  showConsole();
  selectTab(consoleTab, true);
});

function selectTab(tab, focusPane = false) {
  if (tab === consoleTab && !startup.hidden) showConsole();
  const previous = tabs.get(activeTab);
  if (tab !== activeTab) previous?.blur?.();
  activeTab = tab;
  for (const [key, { pane }] of tabs) {
    const active = key === tab;
    key.setAttribute("aria-selected", String(active));
    key.parentElement.toggleAttribute("data-selected", active);
    key.tabIndex = active ? 0 : -1;
    pane.hidden = !active;
  }
  tab.parentElement.scrollIntoView({
    block: "nearest",
    inline: "nearest",
    container: "nearest",
  });
  const current = tabs.get(tab);
  if (current) {
    current.show?.();
    current.layout?.();
    if (focusPane) current.focus?.();
  }
}

function addTab(title, className, kind) {
  const id = `pane-${++tabNumber}`;
  const tab = document.createElement("button");
  tab.id = `${id}-tab`;
  tab.className = "tab-button";
  tab.type = "button";
  tab.tabIndex = -1;
  tab.setAttribute("role", "tab");
  tab.setAttribute("aria-controls", id);
  tab.setAttribute("aria-selected", "false");
  tab.setAttribute("aria-keyshortcuts", "Delete");
  const label = document.createElement("span");
  label.className = "tab-label";
  tab.append(icon(kind), label);

  const pane = document.createElement("div");
  pane.id = id;
  pane.className = className;
  pane.setAttribute("role", "tabpanel");
  pane.setAttribute("aria-labelledby", tab.id);
  pane.hidden = true;

  const chip = document.createElement("div");
  chip.className = "tab";
  chip.setAttribute("role", "presentation");
  // Delete on the tab reaches it from the keyboard.
  const close = document.createElement("button");
  close.className = "tab-close";
  close.type = "button";
  close.tabIndex = -1;
  close.append(icon("close"));
  const setTitle = (value) => {
    label.textContent = value;
    chip.title = value;
    close.setAttribute("aria-label", `Close ${value}`);
  };
  setTitle(title);
  const entry = { pane, chip, setTitle };
  close.addEventListener("click", (event) => {
    event.stopPropagation();
    entry.close?.();
  });
  chip.append(tab, close);
  tabList.append(chip);
  workspace.append(pane);
  tabs.set(tab, entry);
  return { tab, entry };
}

function removeTab(tab) {
  const entry = tabs.get(tab);
  if (!entry) return;
  const neighbor =
    entry.chip.nextElementSibling?.querySelector('[role="tab"]') ??
    entry.chip.previousElementSibling?.querySelector('[role="tab"]') ??
    consoleTab;
  entry.blur?.();
  entry.dispose?.();
  entry.pane.remove();
  entry.chip.remove();
  tabs.delete(tab);
  if (activeTab === tab) {
    selectTab(neighbor, true);
  } else if (document.activeElement === document.body) {
    activeTab.focus();
  }
}

tabList.addEventListener("click", (event) => {
  const tab = event.target.closest('[role="tab"]');
  if (tab) selectTab(tab, true);
});
// A middle click closes a tab, as in a browser.
tabList.addEventListener("auxclick", (event) => {
  if (event.button !== 1) return;
  const tab = event.target.closest(".tab")?.querySelector('[role="tab"]');
  if (tab && tabs.get(tab)?.close) {
    event.preventDefault();
    tabs.get(tab).close();
  }
});
tabList.addEventListener("keydown", (event) => {
  const ordered = [...tabs.keys()];
  const index = ordered.indexOf(event.target);
  if (index < 0) return;
  if (event.key === "Delete" && tabs.get(event.target)?.close) {
    event.preventDefault();
    tabs.get(event.target).close();
    return;
  }
  const next = {
    ArrowLeft: (index + ordered.length - 1) % ordered.length,
    ArrowRight: (index + 1) % ordered.length,
    Home: 0,
    End: ordered.length - 1,
  }[event.key];
  if (next === undefined) return;
  event.preventDefault();
  selectTab(ordered[next]);
  ordered[next].focus();
});
window.addEventListener(
  "keydown",
  (event) => {
    if (
      event.ctrlKey &&
      event.shiftKey &&
      event.code === "Period" &&
      workspace.contains(event.target)
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      activeTab.focus();
    }
  },
  { capture: true },
);

// ================= Settings =================

$("#settings-button").addEventListener("click", () => settings.showModal());
if (!("closedBy" in HTMLDialogElement.prototype)) {
  const outside = (event) => {
    const r = settings.getBoundingClientRect();
    return (
      event.clientX < r.left ||
      event.clientX > r.right ||
      event.clientY < r.top ||
      event.clientY > r.bottom
    );
  };
  let pressedOutside = false;
  settings.addEventListener("pointerdown", (event) => {
    pressedOutside = outside(event);
  });
  settings.addEventListener("pointerup", (event) => {
    if (pressedOutside && outside(event)) settings.close();
  });
}
settings.addEventListener("close", () => tabs.get(activeTab)?.focus?.());

for (const button of document.querySelectorAll("[data-step]")) {
  button.addEventListener("click", () => {
    if (button.dataset.step === "1") fontSizeField.stepUp();
    else fontSizeField.stepDown();
    fontSizeField.dispatchEvent(new Event("input"));
  });
}
fontSizeField.addEventListener("input", () => {
  if (!fontSizeField.validity.valid) return;
  const fontSize = fontSizeField.valueAsNumber;
  savePreferences({ fontSize });
  for (const { term } of tabs.values()) {
    if (term) term.options.fontSize = fontSize;
  }
  tabs.get(activeTab)?.layout?.();
});
preferences.addEventListener("submit", (event) => {
  event.preventDefault();
  if (!window.confirm("Restart NixOS and discard the current guest session?"))
    return;
  const next = {
    cpus: fields.cpus.valueAsNumber,
    memory: fields.memory.valueAsNumber,
  };
  savePreferences(next);
  const url = new URL(location.href);
  url.searchParams.set("cpus", next.cpus);
  url.searchParams.set("mem", next.memory);
  if (url.href === location.href) location.reload();
  else location.assign(url);
});

// ================= Sessions =================

// ghostty-web 0.4.0 exposes the cursor position but does not expose DECSCUSR
// styles from its WASM render state. Keep the final request across PTY chunks.
function terminalWriter(term, allowBlink) {
  const decoder = new TextDecoder();
  let prefix = "";
  return (bytes, done) => {
    if (prefix || bytes.includes(0x1b)) {
      const output = prefix + decoder.decode(bytes);
      prefix = output.match(/\x1b(?:\[[0-6]? ?)?$/)?.[0] ?? "";
      let style;
      for (const match of output.matchAll(/\x1b\[([0-6]?) q/g)) {
        style = Number(match[1]);
      }
      if (style !== undefined) {
        term.options.cursorStyle =
          style >= 5 ? "bar" : style >= 3 ? "underline" : "block";
        term.options.cursorBlink =
          allowBlink && (style === 0 || style % 2 === 1);
      }
    }
    term.write(bytes, done);
  };
}

function makeTerminal(entry) {
  const surface = document.createElement("div");
  surface.className = "terminal-surface";
  entry.pane.append(surface);
  const style = getComputedStyle(entry.pane);
  const allowBlink = !matchMedia("(prefers-reduced-motion: reduce)").matches;
  const term = new Terminal({
    cursorBlink: allowBlink,
    fontFamily: getComputedStyle(surface).fontFamily,
    fontSize: fontSizeField.valueAsNumber || 14,
    theme: {
      background: style.backgroundColor,
      foreground: style.color,
      cursor: style.color,
    },
  });
  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(surface);
  surface.setAttribute("aria-describedby", "tab-shortcut");

  // Soft keyboards can insert plain text without dispatching a keydown.
  const input = surface.querySelector("textarea");
  input?.addEventListener("beforeinput", (event) => {
    if (event.isComposing || event.inputType !== "insertText" || !event.data)
      return;
    event.preventDefault();
    term.input(event.data, true);
  });
  const layout = () => {
    if (!entry.pane.hidden) fit.fit();
  };
  const resize = new ResizeObserver(layout);
  resize.observe(entry.pane);
  Object.assign(entry, {
    term,
    write: terminalWriter(term, allowBlink),
    layout,
    focus: () => term.focus(),
    dispose: () => {
      resize.disconnect();
      term.dispose();
    },
  });
  layout();
  return term;
}

const login = "/run/current-system/sw/bin/bash";

async function openSession(vm, user, app, { select = true } = {}) {
  const abort = new AbortController();
  const name =
    app?.name ?? (++shellNumber === 1 ? "Shell" : `Shell ${shellNumber}`);
  const { tab, entry } = addTab(name, "terminal-pane", "terminal");
  const term = makeTerminal(entry);
  term.onTitleChange((title) => entry.setTitle(title.trim() || name));
  entry.close = () => removeTab(tab);
  const disposeTerminal = entry.dispose;
  let pty;
  entry.dispose = () => {
    abort.abort();
    pty?.close().catch(() => {});
    disposeTerminal();
  };
  if (select) selectTab(tab, true);
  try {
    const args = app
      ? ["-lc", 'exec "$@"', "tabos", ...app.command]
      : ["-lc", 'exec "$SHELL" -l'];
    pty = await vm.spawn(login, args, {
      user,
      cols: term.cols,
      rows: term.rows,
      signal: abort.signal,
    });
    if (abort.signal.aborted) {
      await pty.close();
      return;
    }
    pty.resize(term.cols, term.rows);
    term.onResize(({ cols, rows }) => pty.resize(cols, rows));
    const input = term.onData((data) => pty.write(data).catch(() => {}));
    try {
      // Drain the PTY even while its tab is hidden.
      for await (const bytes of pty.output) {
        if (!abort.signal.aborted)
          await new Promise((done) => entry.write(bytes, done));
      }
      const end = await pty.ended;
      if (!abort.signal.aborted) {
        term.writeln(
          end.type === "exit"
            ? `\r\nSession exited (${end.code}).`
            : "\r\nSession ended.",
        );
      }
    } finally {
      input.dispose();
      await pty.ended.catch(() => {});
    }
  } catch (error) {
    if (!abort.signal.aborted) term.writeln(`\r\n${error.message}`);
  }
}

function openWindow(window) {
  const { tab, entry } = addTab(
    window.title || "Wayland window",
    "wayland-pane",
    "window",
  );
  entry.pane.append(window.element);
  const layout = () => {
    if (!entry.pane.hidden)
      window.resize(entry.pane.clientWidth, entry.pane.clientHeight);
  };
  const resize = new ResizeObserver(layout);
  resize.observe(entry.pane);
  Object.assign(entry, {
    show: window.show,
    focus: window.focus,
    blur: window.blur,
    close: window.close,
    layout,
    dispose: () => resize.disconnect(),
  });
  say("");
  selectTab(tab, true);
  return {
    setTitle: (title) => {
      entry.setTitle(title || "Wayland window");
    },
    remove: () => removeTab(tab),
  };
}

function setupApps(vm, config) {
  $("#new-shell").addEventListener("click", () => {
    menu.hidePopover();
    openSession(vm, config.user);
  });
  const apps = config.apps ?? [];
  const groups = [
    apps.filter((app) => !app.wayland),
    apps.filter((app) => app.wayland),
  ];
  for (const group of groups) {
    if (!group.length) continue;
    const rule = document.createElement("hr");
    rule.className = "menu-rule";
    menu.append(rule);
    for (const app of group) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "menu-item";
      const name = document.createElement("span");
      name.textContent = app.name;
      button.append(icon(app.wayland ? "window" : "terminal"), name);
      menu.append(button);
      button.addEventListener("click", () => {
        menu.hidePopover();
        if (app.wayland) launchWindow(vm, config, app);
        else openSession(vm, config.user, app);
      });
    }
  }
}

async function launchWindow(vm, config, app) {
  const opening = `Opening ${app.name}…`;
  say(opening);
  try {
    const [file, ...args] = app.command;
    const result = await vm.exec(file, args, {
      user: config.user,
      maxBuffer: 65536,
    });
    if (result.exitCode !== 0)
      throw new Error(result.stderr.trim() || "The app exited.");
    if (statusText === opening) say("");
  } catch (error) {
    say(`Could not open ${app.name}. ${error.message}`);
  }
}

// ================= Boot =================

async function boot() {
  // The canvas caches cell widths on open, so load both faces before fitting.
  await Promise.all([
    init(),
    document.fonts.load('400 14px "FiraCode Nerd Font"').catch(() => {}),
    document.fonts.load('700 14px "FiraCode Nerd Font"').catch(() => {}),
  ]);
  const consoleEntry = { pane: consolePane };
  tabs.set(consoleTab, consoleEntry);
  const term = makeTerminal(consoleEntry);
  bootStep("Checking the browser", { pending: true });
  const support = await checkSupport();
  if (!support.ok) {
    bootFailed(
      `This browser cannot run the kernel:\n${support.problems.join("\n")}`,
    );
    return;
  }

  bootStep("Checked the browser");
  bootStep("Reading the guest configuration", { pending: true });
  const response = await fetch("config.json");
  if (!response.ok)
    throw new Error(
      `Could not load guest configuration (HTTP ${response.status})`,
    );
  const config = await response.json();
  $("#host-name").textContent = config.hostName;
  document.title = `${config.hostName} · TabOS`;
  const proxy = new URL(config.wisp, location.href);
  proxy.protocol = proxy.protocol === "https:" ? "wss:" : "ws:";
  const wisp = params.get("wisp") ?? proxy.href;

  bootStep("Read the guest configuration");
  let allocatedMemory;
  let initStarted = false;
  let consoleTail = "";
  const decoder = new TextDecoder();
  const onOutput = (bytes) => {
    consoleEntry.write(bytes);
    if (initStarted) return;

    // NixOS does not use unkernel's distro init, so watch for its PID 1.
    const output = consoleTail + decoder.decode(bytes, { stream: true });
    if (/systemd\[1\]: systemd [^\r\n]* running in system mode/.test(output)) {
      initStarted = true;
      bootStep("Started NixOS init");
      bootStep("Starting guest sessions", { pending: true });
      consoleTail = "";
    } else {
      consoleTail = output.slice(-256);
    }
  };
  const vm = await createKernel({
    shm: Boolean(config.wayland),
    onProgress: (progress) => {
      if (progress.stage === "memory") allocatedMemory = progress.mib;
      reportBoot(progress);
    },
    onOutput,
    distro: new URL(config.image, location.href).href,
    cmdline: `console=hvc0 rdinit=/init kw.user=${config.user}`,
    memoryMiB: memory,
    worker: isolated,
    cpus,
    net: isolated
      ? { kind: "net", backend: { kind: "wisp", servers: wisp } }
      : wispBackend(wisp),
  });

  term.onData((data) => vm.write(data));
  term.onResize(({ cols, rows }) => vm.resize(cols, rows));
  vm.resize(term.cols, term.rows);
  const detachWayland =
    config.wayland &&
    attachWayland(vm, openWindow, (error) => say(String(error)));
  setupApps(vm, config);

  const image = vm.distro;
  if (image) {
    $("#image-info").textContent =
      `${mebibytes(image.size)} ${image.fs.toUpperCase()} · streamed`;
  }
  const running = `${vm.stats().cpus ?? cpus} CPUs · ${allocatedMemory ?? memory} MiB`;
  $("#resources").textContent = running;

  let stopped = false;
  void vm
    .exec("/run/current-system/sw/bin/true", [], {
      user: config.user,
      timeout: 45000,
      signal: AbortSignal.timeout(50000),
    })
    .then((result) => {
      if (result.exitCode !== 0)
        throw new Error(result.stderr.trim() || "Guest session check failed.");
      if (stopped) return;
      newButton.disabled = false;
      bootStep("Guest sessions ready");
      clearInterval(clock);
      const bootTime = elapsed(performance.now() - startedAt);
      $("#boot-time").textContent = bootTime;
      hostState.textContent = running;
      $("#boot-log-slot").replaceWith(bootSteps);
      $("#boot-log").hidden = false;
      // Someone already reading the console keeps it; the shell waits beside.
      const watching = startup.hidden && activeTab === consoleTab;
      showConsole();
      openSession(vm, config.user, undefined, { select: !watching });
    })
    .catch((error) => {
      if (!stopped) {
        showConsole();
        say(`Guest sessions unavailable. ${error.message}`);
      }
    });

  const { kind, code } = await vm.exited;
  stopped = true;
  newButton.disabled = true;
  menu.hidePopover();
  detachWayland && detachWayland();
  const message = `The machine stopped (${kind}, code ${code}). Reload to boot it again.`;
  hostState.textContent = "Stopped";
  if (initStarted) say(message);
  else bootFailed(message);
}

boot().catch((error) => bootFailed(String(error?.message ?? error)));
