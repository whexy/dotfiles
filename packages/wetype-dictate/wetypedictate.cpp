// Dictation on the right Alt key, the way WeType for macOS does it on the
// right Option key: a tap starts listening and the recognised text appears
// as underlined preedit while the user speaks; a second tap stops, and the
// polished transcript replaces the preedit. Escape while listening drops
// the dictation.
//
// The microphone and the network live in a helper process
// (wetype_dictate.py), so nothing here blocks fcitx5's event loop.

#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <ctime>
#include <memory>
#include <string>
#include <vector>

#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventloopinterface.h>
#include <fcitx-utils/handlertable.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/textformatflags.h>
#include <fcitx-utils/trackableobject.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/text.h>
#include <fcitx/userinterface.h>

extern char **environ;

namespace {

FCITX_DEFINE_LOG_CATEGORY(dictateLog, "wetypedictate");
#define DICTATE_WARN() FCITX_LOGC(dictateLog, Warn)

constexpr uint64_t kStatusLingerUsec = 3'000'000;
constexpr uint64_t kReapRetryUsec = 200'000;

std::string unescape(const std::string &in) {
    std::string out;
    out.reserve(in.size());
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] == '\\' && i + 1 < in.size()) {
            ++i;
            out += in[i] == 'n' ? '\n' : in[i];
        } else {
            out += in[i];
        }
    }
    return out;
}

class WetypeDictate : public fcitx::AddonInstance {
public:
    explicit WetypeDictate(fcitx::Instance *instance) : instance_(instance) {
        watchers_.emplace_back(instance_->watchEvent(
            fcitx::EventType::InputContextKeyEvent,
            fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &event) {
                onKey(static_cast<fcitx::KeyEvent &>(event));
            }));
    }

    ~WetypeDictate() override {
        if (pid_ > 0) {
            kill(pid_, SIGTERM);
        }
        closeHelper();
    }

private:
    enum class State { Idle, Listening, Finishing };

    void onKey(fcitx::KeyEvent &event) {
        const bool rightAlt = event.rawKey().sym() == FcitxKey_Alt_R;
        if (!event.isRelease()) {
            tap_ = rightAlt;
            if (rightAlt) {
                event.filterAndAccept();
            } else if (state_ == State::Listening &&
                       event.key().check(FcitxKey_Escape)) {
                cancel();
                swallowEscape_ = true;
                event.filterAndAccept();
            }
            return;
        }
        if (rightAlt) {
            // Right Alt is the dictation key alone: passing it on would
            // toggle the menu bar of apps that open it on an Alt tap.
            event.filterAndAccept();
            if (tap_) {
                toggle(event.inputContext());
            }
            tap_ = false;
        } else if (swallowEscape_ && event.key().check(FcitxKey_Escape)) {
            swallowEscape_ = false;
            event.filterAndAccept();
        }
    }

    void toggle(fcitx::InputContext *ic) {
        if (state_ == State::Idle) {
            start(ic);
        } else if (state_ == State::Listening) {
            // The helper takes stdin's end as the end of speech.
            close(toHelper_);
            toHelper_ = -1;
            state_ = State::Finishing;
        }
    }

    void start(fcitx::InputContext *ic) {
        int in[2], out[2];
        if (pipe2(in, O_CLOEXEC) != 0) {
            DICTATE_WARN() << "pipe failed: " << errno;
            return;
        }
        if (pipe2(out, O_CLOEXEC | O_NONBLOCK) != 0) {
            DICTATE_WARN() << "pipe failed: " << errno;
            close(in[0]);
            close(in[1]);
            return;
        }
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, in[0], STDIN_FILENO);
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
        char helper[] = WETYPE_DICTATE_HELPER;
        char *argv[] = {helper, nullptr};
        const int err =
            posix_spawn(&pid_, helper, &actions, nullptr, argv, environ);
        posix_spawn_file_actions_destroy(&actions);
        close(in[0]);
        close(out[1]);
        if (err != 0) {
            DICTATE_WARN() << "cannot start " << helper << ": " << err;
            pid_ = -1;
            close(in[1]);
            close(out[0]);
            return;
        }
        toHelper_ = in[1];
        fromHelper_ = out[0];
        io_ = instance_->eventLoop().addIOEvent(
            fromHelper_,
            {fcitx::IOEventFlag::In, fcitx::IOEventFlag::Hup,
             fcitx::IOEventFlag::Err},
            [this](fcitx::EventSourceIO *, int, fcitx::IOEventFlags) {
                onOutput();
                return true;
            });

        // Rime's unfinished composition would sit beside the dictation.
        ic->reset();
        ic_ = ic->watch();
        state_ = State::Listening;
        preedit_.clear();
        status_.clear();
        lingerTimer_.reset();
        render();
    }

    void cancel() {
        kill(pid_, SIGTERM);
        finishSession();
    }

    void onOutput() {
        char chunk[4096];
        for (;;) {
            const ssize_t n = read(fromHelper_, chunk, sizeof chunk);
            if (n > 0) {
                buffer_.append(chunk, n);
                continue;
            }
            if (n < 0 && errno == EINTR) {
                continue;
            }
            const bool eof = n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK);
            size_t start = 0;
            for (size_t nl; (nl = buffer_.find('\n', start)) != std::string::npos;
                 start = nl + 1) {
                handleLine(buffer_.substr(start, nl - start));
                if (state_ == State::Idle) {
                    return;
                }
            }
            buffer_.erase(0, start);
            if (eof) {
                // The helper died without a verdict; keep what it heard.
                commit(preedit_);
                finishSession();
            }
            return;
        }
    }

    void handleLine(const std::string &line) {
        const auto tab = line.find('\t');
        const std::string kind = line.substr(0, tab);
        const std::string text =
            tab == std::string::npos ? "" : unescape(line.substr(tab + 1));
        if (kind == "partial") {
            preedit_ = text;
            render();
        } else if (kind == "status") {
            status_ = text;
            render();
        } else if (kind == "final") {
            status_.clear();
            commit(text);
            finishSession();
        } else if (kind == "error") {
            commit(text.empty() ? preedit_ : text);
            finishSession();
            lingerStatus();
        }
    }

    // Dictation follows focus: the preedit, and the text when it is done,
    // go to the input context that has it now.
    fcitx::InputContext *target() {
        auto *now = instance_->mostRecentInputContext();
        auto *before = ic_.get();
        if (now && now != before) {
            if (before) {
                paint(before, "", "");
            }
            ic_ = now->watch();
            return now;
        }
        return before;
    }

    void render() {
        if (auto *ic = target()) {
            paint(ic, preedit_, status_);
        }
    }

    static void paint(fcitx::InputContext *ic, const std::string &preedit,
                      const std::string &status) {
        auto &panel = ic->inputPanel();
        fcitx::Text text;
        if (!preedit.empty()) {
            text.append(preedit, fcitx::TextFormatFlag::Underline);
            text.setCursor(static_cast<int>(text.textLength()));
        }
        if (ic->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
            panel.setClientPreedit(text);
        } else {
            panel.setPreedit(text);
        }
        panel.setAuxUp(fcitx::Text(status));
        ic->updatePreedit();
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    }

    void commit(const std::string &text) {
        auto *ic = target();
        if (!ic) {
            return;
        }
        paint(ic, "", status_);
        if (!text.empty()) {
            ic->commitString(text);
        }
    }

    void lingerStatus() {
        auto *ic = ic_.get();
        if (!ic || status_.empty()) {
            return;
        }
        paint(ic, "", status_);
        lingerTimer_ = instance_->eventLoop().addTimeEvent(
            CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + kStatusLingerUsec, 0,
            [this, ref = ic->watch()](fcitx::EventSourceTime *, uint64_t) {
                if (auto *ic = ref.get(); ic && state_ == State::Idle) {
                    paint(ic, "", "");
                }
                return true;
            });
    }

    void finishSession() {
        closeHelper();
        if (pid_ > 0) {
            zombies_.push_back(pid_);
            pid_ = -1;
            reap();
        }
        if (auto *ic = ic_.get()) {
            paint(ic, "", "");
        }
        preedit_.clear();
        buffer_.clear();
        state_ = State::Idle;
    }

    void closeHelper() {
        io_.reset();
        if (toHelper_ >= 0) {
            close(toHelper_);
            toHelper_ = -1;
        }
        if (fromHelper_ >= 0) {
            close(fromHelper_);
            fromHelper_ = -1;
        }
    }

    // A helper still exiting is waited for on a timer, never blocking the
    // event loop.
    void reap() {
        std::erase_if(zombies_, [](pid_t pid) {
            return waitpid(pid, nullptr, WNOHANG) != 0;
        });
        if (zombies_.empty()) {
            reapTimer_.reset();
            return;
        }
        reapTimer_ = instance_->eventLoop().addTimeEvent(
            CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + kReapRetryUsec, 0,
            [this](fcitx::EventSourceTime *, uint64_t) {
                reap();
                return true;
            });
    }

    fcitx::Instance *instance_;
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>>
        watchers_;
    std::unique_ptr<fcitx::EventSourceIO> io_;
    std::unique_ptr<fcitx::EventSourceTime> lingerTimer_, reapTimer_;
    std::vector<pid_t> zombies_;
    fcitx::TrackableObjectReference<fcitx::InputContext> ic_;
    State state_ = State::Idle;
    bool tap_ = false;
    bool swallowEscape_ = false;
    pid_t pid_ = -1;
    int toHelper_ = -1, fromHelper_ = -1;
    std::string buffer_, preedit_, status_;
};

class WetypeDictateFactory : public fcitx::AddonFactory {
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new WetypeDictate(manager->instance());
    }
};

} // namespace

FCITX_ADDON_FACTORY(WetypeDictateFactory);
