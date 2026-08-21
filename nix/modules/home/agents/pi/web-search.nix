# pi-web-access extension config (~/.pi/web-search.json)
# https://github.com/nicobailon/pi-web-access
{ proxyAccounts }:
{
  # Summarize search results with gpt-5.6-luna, served by the tailnet AI
  # proxy when available and by the OpenCode Go subscription otherwise,
  # instead of the default candidates (claude-haiku-4-5 /
  # gpt-5.3-codex-spark) or whatever model is enabled.
  summaryModel = if proxyAccounts then "ai-proxy/gpt-5.6-luna" else "opencode-go/gpt-5.6-luna";

  # Headless operation: never open a browser/curator window.
  autoOpenBrowser = false;
  # Skip the interactive browser curator entirely; return a model-generated
  # summary directly (no curator page, no browser).
  workflow = "auto-summary";
}
