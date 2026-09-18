# pi-web-access extension config (~/.pi/web-search.json)
# https://github.com/nicobailon/pi-web-access
{ defaults }:
{
  # Summarize search results with the cheap model instead of the default
  # candidates (claude-haiku-4-5 / gpt-5.3-codex-spark) or whatever model
  # is enabled.
  summaryModel = defaults.cheap;

  # Headless operation: never open a browser/curator window.
  autoOpenBrowser = false;
  # Skip the interactive browser curator entirely; return a model-generated
  # summary directly (no curator page, no browser).
  workflow = "auto-summary";
}
