#!/usr/bin/osascript -l JavaScript
// Alfred script filter: the hosts Rex is connected to, each item's arg the
// host's ID for new-session.js. Alfred filters the items by the query.

function run() {
  const rex = Application("Rex Beta");
  // Asking a stopped app for its hosts would launch it on every keystroke.
  if (!rex.running()) {
    return JSON.stringify({
      items: [{ title: "Rex is not running", valid: false }],
    });
  }

  const items = rex
    .hosts()
    .filter((host) => host.connected())
    .map((host) => {
      // Rex names this Mac's own server by its socket URL.
      const local = host.name().startsWith("unix://");
      const name = local ? "This Mac" : host.name();
      return {
        uid: host.id(),
        title: name,
        subtitle: `New Rex session on ${name}`,
        arg: host.id(),
        match: local ? `${name} local` : name,
        icon: { type: "fileicon", path: "/Applications/Rex Beta.app" },
      };
    });

  if (items.length === 0) {
    items.push({ title: "Rex is connected to no host", valid: false });
  }
  return JSON.stringify({ items });
}
