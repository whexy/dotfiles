# Model roster shared by pi and opencode, which both expose every provider
# side by side. Order is pi's Ctrl+P cycling order; `thinkingLevel` is pi's
# per-model default.
{
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  model = id: thinkingLevel: { inherit id thinkingLevel; };
  models = [
    # Daily drivers
    (model "ai-proxy/claude-opus-5-5" "medium")

    # Powerful intelligence
    (model "ai-proxy/claude-fable-5-1" "high")
    (model "ai-proxy/gpt-6-astra" "high")

    # DEI models
    (model "openrouter/meta/muse-spark-1.3-contributor" "max")
    (model "ai-proxy/gpt-6-sol" "high")
    (model "ai-proxy/grok-4.7" "high")
    (model "openrouter/xiaomi/mimo-v2.6-pro" null)
    (model "openrouter/qwen/qwen3.8-max-0902" null)
    (model "openrouter/z-ai/glm-5.3" "max")
    (model "ai-proxy/gemini-3.8-flash" "high")
    (model "ai-proxy/gpt-6-luna" "max")

    # API billing (paid by lab)
    (model "openai/gpt-6-astra" null)
    (model "openai/gpt-6-sol" null)
    (model "openai/gpt-6-luna" null)
    (model "anthropic/claude-fable-5-1" null)
    (model "anthropic/claude-opus-5-5" null)
    (model "anthropic/claude-sonnet-5" null)
  ];
  modelEnabled =
    model:
    if lib.hasPrefix "ai-proxy/" model.id then
      proxyAccounts
    else if
      lib.hasPrefix "openrouter/" model.id
      || lib.hasPrefix "openai/" model.id
      || lib.hasPrefix "anthropic/" model.id
    then
      apiAccounts
    else
      true;
in
lib.filter modelEnabled models
