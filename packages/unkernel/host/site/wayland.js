const relayPort = 1023;

function guestBuffers(shm) {
  async function read(file, offset, target) {
    target.set(await file.read(offset, target.length));
  }

  return {
    async open(handle) {
      if (handle.kind !== "kwshm") {
        throw new Error("Wayland relay needs kwshm buffers.");
      }
      const file = await shm.openId(handle.id);
      if (file.size !== handle.size) {
        await file.close();
        throw new Error("Wayland buffer size differs from its guest export.");
      }
      return file;
    },
    view(file, offset, length) {
      if (!file.inPlace) return null;
      try {
        return file.views(offset, length);
      } catch (error) {
        if (error.code !== "EAGAIN") throw error;
        return null;
      }
    },
    read,
    async readv(file, reads) {
      await Promise.all(
        reads.map(({ offset, dst }) => read(file, offset, dst)),
      );
    },
    close(file) {
      void file.close().catch(() => {});
    },
  };
}

function windowTitle(win) {
  return (win.title !== win.key && win.title) || win.appId || "Wayland window";
}

// One relay carries every toplevel. It connects when the first GUI app opens.
export function attachWayland(
  vm,
  openWindow,
  reportError,
  container = document.getElementById("workspace"),
) {
  if (!vm.vsock || !vm.shm) {
    throw new Error("Wayland needs vsock and guest shared memory.");
  }

  const listener = vm.vsock.listen(relayPort);
  const windows = new Map();
  let compositor;
  let selected;
  let stopped = false;
  let queued = false;

  function reconcile() {
    if (!compositor || stopped) return;
    for (const win of compositor.view.windows()) {
      const title = windowTitle(win);
      const existing = windows.get(win.key);
      if (existing) {
        if (title !== existing.title) {
          existing.title = title;
          existing.tab.setTitle(title);
        }
        continue;
      }

      const { conn, surface, element } = win;
      Object.assign(element.style, { top: "0", left: "0", overflow: "clip" });
      const focusKeyboard = () => {
        selected = win.key;
        compositor?.input.focus(conn, surface);
      };
      element.addEventListener("pointerdown", focusKeyboard, { capture: true });
      let width = 0;
      let height = 0;
      compositor.engine.setVisible(conn, surface, false);
      const tab = openWindow({
        title,
        element,
        show() {
          compositor?.engine.setVisible(conn, surface, true);
          if (compositor?.view.window(conn, surface)?.minimized) {
            compositor.wm.restore(conn, surface);
          }
        },
        focus: focusKeyboard,
        blur() {
          if (selected === win.key) {
            selected = undefined;
            compositor?.input.blur();
          }
          compositor?.engine.setVisible(conn, surface, false);
        },
        close() {
          compositor?.engine.close(conn, surface);
        },
        resize(nextWidth, nextHeight) {
          nextWidth = Math.floor(nextWidth);
          nextHeight = Math.floor(nextHeight);
          if (
            !compositor ||
            nextWidth < 1 ||
            nextHeight < 1 ||
            (nextWidth === width && nextHeight === height)
          )
            return;
          width = nextWidth;
          height = nextHeight;
          compositor.engine.setBounds(width, height);
          compositor.engine.setWindowPosition(conn, surface, 0, 0);
          compositor.engine.requestResize(conn, surface, width, height);
        },
      });
      windows.set(win.key, { tab, title });
    }
  }

  function onWindowsChange() {
    if (queued || stopped) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      reconcile();
    });
  }

  function unmount(win) {
    const entry = windows.get(win.key);
    windows.delete(win.key);
    if (selected === win.key) selected = undefined;
    entry?.tab.remove();
  }

  async function start() {
    const first = await listener.accept();
    if (!first || stopped) {
      first?.reset();
      return;
    }
    try {
      const { createWland, createStreamLink } =
        await import("./wland/client.mjs");
      if (stopped) {
        first.reset();
        return;
      }
      // Keep accepting after a link drops so launching another app can reconnect.
      const connections = {
        async *[Symbol.asyncIterator]() {
          yield first;
          yield* listener;
        },
        close: () => listener.close(),
      };
      const instance = await createWland({
        container,
        wasm: new URL("./wland/wland.wasm", import.meta.url),
        link: createStreamLink(connections),
        buffers: guestBuffers(vm.shm),
        autoFocus: false,
        manageDisplay: false,
        decorations: "server",
        shortcuts: false,
        dnd: false,
        interactive: () => true,
        mount() {
          // The tab owns the element. Reconcile after wland presents its frame.
        },
        unmount,
        onWindowsChange,
        onEvent(event) {
          if (!stopped && event.type === "error") reportError(event.detail);
        },
      });
      if (stopped) instance.dispose();
      else {
        compositor = instance;
        reconcile();
      }
    } catch (error) {
      first.reset();
      listener.close();
      if (!stopped) reportError(error.message);
    }
  }

  void start();
  return () => {
    stopped = true;
    listener.close();
    const instance = compositor;
    compositor = undefined;
    instance?.dispose();
  };
}
