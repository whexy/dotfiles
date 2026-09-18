// Pi extension: emit an OSC 777 desktop notification when the agent settles,
// i.e. it finished the run and is waiting for the user (no auto-retry,
// auto-compaction retry, or queued follow-up left).
//
// OSC 777 passes transparently through SSH, so Ghostty on the local machine
// receives and displays it without any local helper programs.
//
// Format: ESC ] 777 ; notify ; <title> ; <body> ST
//
// Written directly to the controlling terminal device — bypasses the TUI
// redraw and works transparently over SSH.
import { writeFile } from "node:fs/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("agent_settled", async (_event, ctx) => {
    // Another extension may have already started the next run; only notify
    // when pi is actually back to waiting for input.
    if (!ctx.isIdle()) return;

    let body = ctx.sessionManager.getSessionName() ?? "Ready for input";
    // Strip control characters so the body cannot break the OSC sequence.
    body = body.replace(/[\x00-\x1f\x7f]/g, " ");
    await writeFile("/dev/tty", `\x1b]777;notify;Pi;${body}\x1b\\`).catch(
      () => {},
    );
  });
}
