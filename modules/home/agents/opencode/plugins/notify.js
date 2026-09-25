// OpenCode plugin: emit an OSC 777 desktop notification when the session goes
// idle (i.e., the agent finishes a turn and returns control to the user).
//
// OSC 777 passes transparently through SSH, so Ghostty on the local machine
// receives and displays it without any local helper programs.
//
// Format: ESC ] 777 ; notify ; <title> ; <body> ST
export const NotifyPlugin = async ({ client }) => ({
  event: async ({ event }) => {
    if (event.type !== "session.idle") return;

    const { sessionID } = event.properties;

    const { data: session } = await client.session.get({
      path: { id: sessionID },
    });
    const { data: todos } = await client.session.todo({
      path: { id: sessionID },
    });

    const remaining = todos.filter(
      (t) => t.status === "pending" || t.status === "in_progress",
    ).length;

    let body = session.title || "Session idle";
    if (remaining > 0)
      body += ` — ${remaining} todo${remaining > 1 ? "s" : ""} remaining`;
    if (session.summary?.files > 0) {
      const { files, additions, deletions } = session.summary;
      body += ` (${files} file${files > 1 ? "s" : ""}, +${additions}/-${deletions})`;
    }

    // Strip control characters so the body cannot break the OSC sequence.
    body = body.replace(/[\x00-\x1f\x7f]/g, " ");

    // Write directly to the controlling terminal device — bypasses the TUI
    // and works transparently over SSH. Headless runs have no terminal.
    const { writeFile } = await import("node:fs/promises");
    await writeFile("/dev/tty", `\x1b]777;notify;OpenCode;${body}\x1b\\`).catch(
      () => {},
    );
  },
});
