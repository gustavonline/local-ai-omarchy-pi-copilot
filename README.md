# Local AI Omarchy Pi Copilot

An opt-in, event-driven Omarchy copilot that uses an isolated, minimal
[Pi](https://pi.dev/) session and a local OpenAI-compatible model to produce
small proactive suggestions.

The plugin is intentionally **not** a coding agent, model manager, or unattended
computer-use agent. It observes filtered active-window metadata, asks the local
model whether one useful suggestion exists, and displays the result in a
bottom-right card that never steals focus.

## Boundaries

This project is independent from both:

- `omarchy-llama-cpp-local-ai`, which may provide and switch the inference
  endpoint but is not required;
- `local-ai-pi-worker`, which may receive an explicitly delegated heavy task
  but is not required.

The default Copilot loop has no tools, skills, extensions, project context,
session history, screenshots, shell, or filesystem access. Pi runs with:

```text
--no-tools --no-skills --no-extensions --no-context-files --no-session
```

The only automatic model input in v0.1 is the allow/deny-filtered active app,
window title, workspace, and matching user-approved playbook hints.

## What it does

- Starts after graphical login when toggled on and remains off when toggled off.
- Listens to Hyprland events and debounces app/workspace changes.
- Uses a dedicated Pi home and a runtime-derived model catalog.
- Rate-limits and confidence-gates suggestions.
- Shows suggestions at the bottom right without taking keyboard focus.
- Offers explicit **Dismiss**, **Copy draft**, **Remember**, and optional
  **Delegate** actions.
- Stores only a small local status file, an explicit editable playbook, and a
  bounded metadata-only audit log.

## Requirements

- Current Omarchy/Hyprland
- Python 3.11 or newer
- Pi CLI
- A local OpenAI Chat Completions-compatible endpoint with `/v1/models`
- `hyprctl`, `systemctl`, `wl-copy`, and `omarchy`

## Install

```bash
omarchy plugin add https://github.com/gustavonline/local-ai-omarchy-pi-copilot --enable --yes
install -Dm600 \
  ~/.config/omarchy/plugins/io.github.gustavonline.local-ai-pi-copilot/local-ai-pi-copilot.example.toml \
  ~/.config/omarchy/local-ai-pi-copilot.toml
```

Edit the endpoint and optional runtime start/delegation commands, then run:

```bash
~/.config/omarchy/plugins/io.github.gustavonline.local-ai-pi-copilot/local-ai-pi-copilot \
  --config ~/.config/omarchy/local-ai-pi-copilot.toml doctor --online
```

Open the bar dropdown and select **Turn on**. Enabling installs and enables one
sandboxed systemd user service. Disabling stops that service and prevents it
from starting at future logins.

See [SETUP.md](SETUP.md) for runtime integration examples.

## Configuration

The TOML file has five independent sections:

- `[runtime]`: endpoint, model selection, Pi output limit, and an optional
  direct argv used to start an unavailable runtime;
- `[observer]`: debounce, cooldown, timeout, confidence, TTL, and hourly cap;
- `[privacy]`: whether window titles may be shared locally plus deny rules;
- `[delegation]`: optional heavy-harness argv, launched only by a user click;
- `[playbook]`: explicit editable rule file.

Secrets do not belong in TOML. `runtime.api_key_env` names an environment
variable; it never stores the value. For a loopback llama.cpp process, the
Copilot can instead discover the matching `--api-key` from that same user's
process arguments. Pi requires the resolved credential, so it is copied only
to the dedicated mode-`0600` machine-local Pi catalog; it never appears in UI,
logs, repository files, or status output.

## Controls

- Left-click: open the Copilot dropdown.
- Right-click: turn the Copilot on/off.
- Middle-click: pause/resume observation.
- Dropdown: lifecycle, health, privacy boundary, test suggestion, settings, and
  playbook controls.
- Suggestion card: dismiss, copy, remember, or explicitly delegate.

## Privacy and safety

Turning the Copilot off means its observer/Pi process is not running. It does
not stop a shared inference server because that server may still be used by
Local AI, Pi workers, Codex, or another client.

The generated systemd unit uses `NoNewPrivileges`, read-only home protection,
private devices/tmp, a strict filesystem view, and write access only to the
Copilot's dedicated state and Pi directories. Model output is treated as data:
it can populate bounded suggestion fields, but it cannot choose commands.

The optional delegation command is fixed by the user in TOML. Only the bounded
task text is appended, and it is opened in a visible terminal after the user
clicks **Delegate**.

## Verification

```bash
./test.sh
```

Tests use fake Pi, Hyprland, systemd, and OpenAI endpoints and never touch the
live desktop or inference service.

## Remove

Turn the Copilot off before removing the plugin:

```bash
~/.config/omarchy/plugins/io.github.gustavonline.local-ai-pi-copilot/local-ai-pi-copilot \
  --config ~/.config/omarchy/local-ai-pi-copilot.toml disable
omarchy plugin remove io.github.gustavonline.local-ai-pi-copilot --yes
```

The machine-local TOML, playbook, and audit state are intentionally left for
the user to inspect or delete.

## License

MIT.
