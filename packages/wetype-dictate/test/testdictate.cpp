// Drives the addon through fcitx5's test frontend with test/fake-helper.sh
// in place of the real helper.

#include <cstdlib>
#include <ctime>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <testfrontend_public.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventloopinterface.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/macros.h>
#include <fcitx-utils/testing.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>

using namespace fcitx;

namespace {

// Long enough for the fake helper to start and answer.
constexpr uint64_t kSettleUsec = 500'000;

struct Steps {
    Instance *instance;
    std::vector<std::function<void()>> steps;
    size_t next = 0;
    std::unique_ptr<EventSourceTime> timer;

    void run() {
        if (next == steps.size()) {
            instance->exit();
            return;
        }
        steps[next++]();
        timer = instance->eventLoop().addTimeEvent(
            CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + kSettleUsec, 0,
            [this](EventSourceTime *, uint64_t) {
                run();
                return true;
            });
    }
};

std::string preedit(InputContext *ic) {
    const auto &panel = ic->inputPanel();
    return panel.clientPreedit().toString() + panel.preedit().toString();
}

} // namespace

int main() {
    setupTestingEnvironmentPath(TEST_DIR, {"addons", FCITX_ADDON_DIR},
                                {"data"});
    char arg0[] = "testdictate";
    char arg1[] = "--disable=all";
    char arg2[] = "--enable=testim,testfrontend,testui,wetypedictate";
    char *argv[] = {arg0, arg1, arg2};
    Instance instance(FCITX_ARRAY_SIZE(argv), argv);
    instance.addonManager().registerDefaultLoader(nullptr);

    AddonInstance *frontend = nullptr;
    ICUUID uuid{};
    InputContext *ic = nullptr;
    auto key = [&](const char *name, bool release) {
        return frontend->call<ITestFrontend::sendKeyEvent>(uuid, Key(name),
                                                           release);
    };
    auto tap = [&] {
        FCITX_ASSERT(key("F19", false));
        FCITX_ASSERT(key("F19", true));
    };

    Steps steps{&instance, {}};
    steps.steps = {
        [&] {
            frontend = instance.addonManager().addon("testfrontend");
            FCITX_ASSERT(instance.addonManager().addon("wetypedictate"));
            uuid = frontend->call<ITestFrontend::createInputContext>("app");
            ic = instance.inputContextManager().findByUUID(uuid);
            // Every commit this test expects, in order.
            for (const char *text :
                 {"One, two.\nThree \\o/", "one two", "one two"}) {
                frontend->call<ITestFrontend::pushCommitExpectation>(text);
            }
            // Other keys start nothing.
            key("Super_R", false);
            key("Super_R", true);
            key("Alt_R", false);
            key("Alt_R", true);
        },
        [&] {
            FCITX_ASSERT(preedit(ic).empty()) << preedit(ic);
            setenv("FAKE_MODE", "final", 1);
            tap();
        },
        [&] {
            FCITX_ASSERT(preedit(ic) == "one two") << preedit(ic);
            tap();
        },
        [&] {
            FCITX_ASSERT(preedit(ic).empty()) << preedit(ic);
            // Escape drops the dictation and commits nothing.
            tap();
        },
        [&] {
            FCITX_ASSERT(preedit(ic) == "one two") << preedit(ic);
            FCITX_ASSERT(key("Escape", false));
            FCITX_ASSERT(key("Escape", true));
            FCITX_ASSERT(preedit(ic).empty()) << preedit(ic);
        },
        [&] {
            // A helper error commits what was heard.
            setenv("FAKE_MODE", "error", 1);
            tap();
        },
        [&] { tap(); },
        [&] {
            FCITX_ASSERT(preedit(ic).empty()) << preedit(ic);
            FCITX_ASSERT(ic->inputPanel().auxUp().toString() ==
                         "Dictation failed")
                << ic->inputPanel().auxUp().toString();
            // So does a helper that dies.
            setenv("FAKE_MODE", "crash", 1);
            tap();
        },
        [&] { tap(); },
        [&] { FCITX_ASSERT(preedit(ic).empty()) << preedit(ic); },
    };
    instance.eventDispatcher().schedule([&] { steps.run(); });
    instance.exec();
    return 0;
}
