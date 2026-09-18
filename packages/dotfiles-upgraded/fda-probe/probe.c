#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef PROBE_REVISION
#define PROBE_REVISION "1"
#endif

/* Keep the responsible native process alive while the activation-like chain
 * crosses into the user's launchd context. exec would discard that boundary. */
int main(int argc, char **argv) {
  if (argc != 3 || geteuid() != 0) {
    fprintf(stderr, "usage (as root): fda-probe USER ABSOLUTE_NIX_BASH\n");
    return 2;
  }
  struct passwd *user = getpwnam(argv[1]);
  if (user == NULL || user->pw_uid == 0 || argv[2][0] != '/') {
    fprintf(stderr, "expected an existing non-root user and absolute bash path\n");
    return 2;
  }
  char uid[32];
  snprintf(uid, sizeof(uid), "%u", (unsigned)user->pw_uid);
  printf("Dotfiles FDA probe revision %s; target uid=%s\n", PROBE_REVISION, uid);
  fflush(stdout);

  const char *script =
      "set -eu\n"
      "target=\"$HOME/Library/Application Support/Firefox\"\n"
      "printf 'user=%s bash=%s target=%s\\n' \"$(/usr/bin/id -un)\" \"$BASH\" \"$target\"\n"
      "if [ ! -d \"$target\" ]; then echo 'FAIL: Firefox directory unavailable'; exit 1; fi\n"
      "probe=$(/usr/bin/mktemp -d \"$target/.dotfiles-fda-probe.XXXXXXXX\")\n"
      "trap '/bin/rm -f \"$probe/link\"; /bin/rmdir \"$probe\"' EXIT\n"
      "/bin/ln -s /dev/null \"$probe/link\"\n"
      "echo 'PASS: created a temporary symlink inside Firefox application data'\n";

  pid_t pid = fork();
  if (pid == -1) {
    perror("fork");
    return 1;
  }
  if (pid == 0) {
    /* The outer Nix Bash models darwin-rebuild/activate; the inner one models
     * Home Manager. Arguments remain positional, never interpolated as code. */
    execl(argv[2], argv[2], "-c",
          "exec /bin/launchctl asuser \"$1\" /usr/bin/sudo -n -u \"$2\" --set-home -- \"$3\" -c \"$4\"",
          "fda-probe", uid, argv[1], argv[2], script, (char *)NULL);
    perror("exec bash");
    _exit(127);
  }
  int status;
  while (waitpid(pid, &status, 0) == -1) {
    if (errno == EINTR) continue;
    perror("waitpid");
    return 1;
  }
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  fprintf(stderr, "probe child terminated by signal\n");
  return 1;
}
