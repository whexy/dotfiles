#!/usr/bin/osascript -l JavaScript
// Alfred action: a new Rex session on the host whose ID hosts.js passed.

function run(argv) {
  const rex = Application("Rex Beta");
  rex.newSession({ on: rex.hosts.byId(argv[0]) });
  rex.activate();
}
