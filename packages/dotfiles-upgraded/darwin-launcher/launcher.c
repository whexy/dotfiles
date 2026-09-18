#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static volatile sig_atomic_t child = 0;
static void stop(int sig) {
  stopping = 1;
  if (child > 0) kill((pid_t)child, sig);
}

/* Stay alive as TCC's signed responsible process. Only launch a fixed,
 * root-managed entrypoint; there is no caller-supplied command interface. */
int main(void) {
  if (geteuid() != 0) {
    fprintf(stderr, "Dotfiles Updater must run as a root LaunchDaemon\n");
    return 1;
  }
  struct sigaction action = {0};
  action.sa_handler = stop;
  sigemptyset(&action.sa_mask);
  sigaction(SIGTERM, &action, NULL);
  sigaction(SIGINT, &action, NULL);
  sigset_t blocked, old;
  sigemptyset(&blocked);
  sigaddset(&blocked, SIGTERM);
  sigaddset(&blocked, SIGINT);
  while (!stopping) {
    sigprocmask(SIG_BLOCK, &blocked, &old);
    pid_t pid = fork();
    if (pid == 0) {
      signal(SIGTERM, SIG_DFL);
      signal(SIGINT, SIG_DFL);
      sigprocmask(SIG_SETMASK, &old, NULL);
      execl("/run/current-system/sw/bin/dotfiles-upgraded-service",
            "dotfiles-upgraded-service", (char *)NULL);
      perror("start dotfiles-upgraded-service");
      _exit(127);
    }
    child = pid > 0 ? pid : 0;
    sigprocmask(SIG_SETMASK, &old, NULL);
    if (pid < 0) {
      perror("fork");
      return 1;
    }
    int status;
    while (waitpid(pid, &status, 0) < 0) {
      if (errno == EINTR) continue;
      perror("waitpid");
      return 1;
    }
    sigprocmask(SIG_BLOCK, &blocked, &old);
    child = 0;
    sigprocmask(SIG_SETMASK, &old, NULL);
    if (!stopping) sleep(10);
  }
  return 0;
}
