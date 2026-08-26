// OpenCode plugin: emit an OSC 777 desktop notification when the session goes
// idle (i.e., the agent finishes a turn and returns control to the user).
//
// OSC 777 passes transparently through SSH, so Ghostty on the local machine
// receives and displays it without any local helper programs.
//
// Format: ESC ] 777 ; notify ; <title> ; <body> ST
//
// V2 port: the loader requires a default-exported { id, setup } module. The
// plugin context does not expose the todo list, so the body only carries the
// session title.
import { writeFile } from "node:fs/promises";

export default {
  id: "dotfiles.notify",
  async setup(ctx) {
    // Detached loop; plugin unload closes the underlying stream.
    void (async () => {
      for await (const event of ctx.event.subscribe()) {
        if (event.type !== "session.idle") continue;
        let body = "Session idle";
        const sessionID = event.properties?.sessionID;
        if (sessionID) {
          const session = await ctx.session
            .get({ sessionID })
            .catch(() => null);
          if (session?.title) body = session.title;
        }
        // Strip control characters so the title cannot break the OSC sequence.
        body = body.replace(/[\x00-\x1f\x7f]/g, " ");
        // Write directly to the controlling terminal device — bypasses the TUI
        // and works transparently over SSH.
        await writeFile(
          "/dev/tty",
          "\x1b]777;notify;OpenCode;" + body + "\x1b\\",
        ).catch(() => {});
      }
    })();
  },
};
