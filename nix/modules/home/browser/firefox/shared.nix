# Platform-independent Firefox configuration, shared by:
# - ../firefox.nix          (Home Manager on NixOS/Darwin, via programs.firefox)
# - nix/packages/firefox-windows-profile (plain file bundle for Windows Firefox)
#
# Platform-specific settings (macOS fullscreen quirks, HiDPI compensation) stay
# in firefox.nix; everything here must make sense on any OS.
let
  # Force-install an extension from addons.mozilla.org. Firefox downloads the
  # latest build itself and keeps it up to date, so no hashes to bump here.
  forceInstall = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "force_installed";
  };
in
{
  # Path to the userChrome.css (moves the tab strip below the content area).
  userChrome = ./userChrome.css;

  policies = {
    DisableAccounts = true;
    DisableFirefoxStudies = true;
    DisableTelemetry = true;

    GenerativeAI = {
      Enabled = false;
      Chatbot = false;
      SmartWindow = false;
      LinkPreviews = false;
      TabGroups = false;
      Locked = true;
    };

    FirefoxSuggest = {
      WebSuggestions = false;
      SponsoredSuggestions = false;
      ImproveSuggest = false;
      Locked = true;
    };
    SearchSuggestEnabled = false;

    # 1Password owns credentials, addresses, and payment methods.
    PasswordManagerEnabled = false;
    OfferToSaveLogins = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;

    # Prefer encrypted DNS without breaking Tailscale or split DNS.
    DNSOverHTTPS = {
      Enabled = true;
      Fallback = true;
      Locked = false;
    };

    EnableTrackingProtection = {
      Value = true;
      Category = "strict";
      Locked = true;
    };
    HttpsOnlyMode = "enabled";

    # Remove identifying history while retaining logins, site state, and
    # cache for normal browsing performance.
    SanitizeOnShutdown = {
      History = true;
      FormData = true;
      Cookies = false;
      Sessions = false;
      SiteSettings = false;
      Cache = false;
      Locked = true;
    };

    FirefoxHome = {
      Search = true;
      TopSites = false;
      Highlights = false;
      Pocket = false;
      Stories = false;
      SponsoredTopSites = false;
      SponsoredPocket = false;
      SponsoredStories = false;
      Snippets = false;
      Weather = false;
      Locked = true;
    };

    Permissions = {
      Camera.BlockNewRequests = false;
      Microphone.BlockNewRequests = false;
      Location.BlockNewRequests = false;
      Notifications.BlockNewRequests = false;
      Autoplay.Default = "block-audio";
    };

    ExtensionSettings = {
      # uBlacklist
      "@ublacklist" = forceInstall "ublacklist";
      # AdGuard AdBlocker
      "adguardadblocker@adguard.com" = forceInstall "adguard-adblocker";
      # AdGuard VPN
      "adguard-vpn@adguard.com" = forceInstall "adguard-vpn";
      # Firenvim (also needs `:call firenvim#install(0)` on the Neovim side)
      "firenvim@lacamb.re" = forceInstall "firenvim";
      # Tampermonkey
      "firefox@tampermonkey.net" = forceInstall "tampermonkey";
      # uBlock Origin
      "uBlock0@raymondhill.net" = forceInstall "ublock-origin";
      # Vimium
      "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = forceInstall "vimium-ff";
      # 1Password
      "{d634138d-c276-4fc8-924b-40a0ea21d284}" = forceInstall "1password-x-password-manager";
    };
  };

  # Profile preferences (user.js on Windows, HM-managed prefs elsewhere).
  settings = {
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    "browser.urlbar.scotchBonnet.enableOverride" = false;

    # Never restore the previous session, including after a crash.
    "browser.startup.page" = 1;
    "browser.sessionstore.resume_from_crash" = false;

    # Keep crash diagnostics local unless explicitly submitted.
    "browser.crashReports.unsubmittedCheck.enabled" = false;
    "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
    "browser.tabs.crashReporting.sendReport" = false;
  };

  # Neutral search engine description. Home Manager renders this into
  # search.json.mozlz4; the Windows bundle renders it into the SearchEngines
  # enterprise policy (that file is profile-path-hashed, so it cannot be
  # reused across machines).
  search = {
    default = "Unduck";
    engines.Unduck = {
      url = "https://flashbang.tech?q={searchTerms}";
      suggestUrl = "https://flashbang.tech/suggest?q={searchTerms}&sp=google";
    };
  };
}
