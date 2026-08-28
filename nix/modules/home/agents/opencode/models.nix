# OpenCode 2 dropped provider whitelist/blacklist. The agent-models.js plugin
# enforces these allow-lists on the assembled catalog, including
# mode-expanded entries like gpt-5.6-fast, which config-level model overrides
# cannot hide.
{
  opencode-go = [
    "deepseek-v4-flash"
    "deepseek-v4-pro"
    "grok-4.6"
    "gpt-5.6-luna"
    "qwen3.8-max"
    "glm-5.3-flash"
  ];
  openai = [
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "gpt-5.6-luna"
  ];
  anthropic = [
    "claude-opus-5"
    "claude-sonnet-5"
    "claude-fable-5"
  ];
  deepseek = [
    "deepseek-v4-flash"
    "deepseek-v4-pro"
  ];
  openrouter = [
    "z-ai/glm-5.3-flash"
  ];
}
