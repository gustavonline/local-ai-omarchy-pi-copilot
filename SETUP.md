# Runtime and delegation setup

The Copilot is a client. It does not own llama.cpp, download a model, alter GPU
settings, or replace an existing runtime controller.

## Standalone endpoint

If another service already keeps a model available, the minimal configuration
is:

```toml
[runtime]
endpoint = "http://127.0.0.1:8080/v1"
model = "auto"
start_command = []
```

`auto` selects the first model returned by `/v1/models`. Set the exact ID to
fail closed when the wrong model is served.

## Optional Local AI integration

The separate Local AI Omarchy plugin may start a runtime profile when the
endpoint is unavailable:

```toml
[runtime]
endpoint = "http://127.0.0.1:8080/v1"
model = "auto"
start_command = [
  "/home/you/.config/omarchy/plugins/gustav.local-ai/local-ai-control",
  "--config",
  "/home/you/.config/omarchy/local-ai.toml",
  "start",
  "Q4",
]
```

This is a one-way, optional integration. The Copilot never rewrites Local AI's
TOML and never stops the shared runtime when the Copilot is disabled.

## Model choice

Prefer the fastest local instruction model that reliably returns short JSON.
A Q4 model is normally the right starting point. On the current Strix Halo
machine the existing Qwen 3.8 27B Q4 profile is practical; an 8B Q4 model can be
substituted later without changing the plugin architecture.

The model's served context is discovered from `/v1/models`. The configured
`context_window` is only a fallback for runtimes that do not publish metadata.

When a loopback llama.cpp endpoint requires authentication, the Copilot first
uses `runtime.api_key_env` and otherwise finds the key on a matching running
`llama-server` process by alias and port. The resolved key exists only in the
Copilot's private Pi catalog. For another runtime, place the key in a named
environment variable and set `api_key_env` to that variable name.

## Optional heavy delegation

Delegation is a separate adapter. For `local-ai-pi-worker`:

```toml
[delegation]
command = ["pi-worker", "--thinking", "low", "--no-web", "--"]
launch_in_terminal = true
```

The Copilot remains fully functional when `pi-worker` is absent. With another
harness, replace the fixed argv with that harness's non-shell CLI invocation.

## Health checks

Offline configuration and dependency audit:

```bash
local-ai-pi-copilot doctor
```

Include endpoint discovery and generation of the isolated Pi catalog:

```bash
local-ai-pi-copilot doctor --online
```

Inspect the exact systemd unit before enabling it:

```bash
local-ai-pi-copilot render-service
```
