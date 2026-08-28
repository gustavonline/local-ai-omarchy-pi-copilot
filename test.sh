#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d)
server_pid=""
cleanup() {
  if [[ -n $server_pid ]]; then kill "$server_pid" >/dev/null 2>&1 || true; fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.gustavonline.local-ai-pi-copilot" and
  .version == "0.1.0" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml"
' "$plugin_dir/manifest.json" >/dev/null

python3 -m py_compile "$plugin_dir/local-ai-pi-copilot"
for file in "$plugin_dir/local-ai-pi-copilot" "$plugin_dir/test.sh" "$plugin_dir/tests/fake-pi" "$plugin_dir/tests/fake-hyprctl" "$plugin_dir/tests/fake-systemctl"; do
  [[ -x $file ]] || { printf 'Expected executable: %s\n' "$file" >&2; exit 1; }
done

port_file="$test_root/port"
python3 "$plugin_dir/tests/fake-openai-server.py" "$port_file" &
server_pid=$!
for _ in $(seq 1 50); do [[ -s $port_file ]] && break; sleep 0.05; done
[[ -s $port_file ]]
port=$(<"$port_file")

config="$test_root/config.toml"
sed \
  -e "s#http://127.0.0.1:8080/v1#http://127.0.0.1:${port}/v1#" \
  -e 's#command = \["pi-worker", "--thinking", "low", "--no-web", "--"\]#command = []#' \
  -e "s#~/.config/omarchy/local-ai-pi-copilot-playbook.json#${test_root}/playbook.json#" \
  "$plugin_dir/local-ai-pi-copilot.example.toml" >"$config"

export LOCAL_AI_COPILOT_STATE_DIR="$test_root/state"
export LOCAL_AI_COPILOT_PI_DIR="$test_root/pi"
export LOCAL_AI_COPILOT_UNIT_DIR="$test_root/units"
export LOCAL_AI_COPILOT_PI="$plugin_dir/tests/fake-pi"
export LOCAL_AI_COPILOT_HYPRCTL="$plugin_dir/tests/fake-hyprctl"
export LOCAL_AI_COPILOT_SYSTEMCTL="$plugin_dir/tests/fake-systemctl"

"$plugin_dir/local-ai-pi-copilot" --config "$config" doctor --online | jq -e '
  .ok and .checks.runtime.ok and (.checks.runtime.detail | contains("32768 tokens"))
' >/dev/null

jq -e '
  .providers["copilot-local"].baseUrl | contains("127.0.0.1")
' "$test_root/pi/models.json" >/dev/null
jq -e '
  .providers["copilot-local"].models[0] |
  .id == "test-local-model" and .contextWindow == 32768 and .maxTokens == 512 and .reasoning == false
' "$test_root/pi/models.json" >/dev/null
jq -e '.providers["copilot-local"].authHeader == false' "$test_root/pi/models.json" >/dev/null

context='{"appId":"org.example.App","title":"Example document","workspace":"1"}'
"$plugin_dir/local-ai-pi-copilot" --config "$config" evaluate --context-json "$context" | jq -e '
  .title == "Prepare the next step" and .confidence == 0.91
' >/dev/null
jq -e '.id and .context.appId == "org.example.App"' "$test_root/state/suggestion.json" >/dev/null

"$plugin_dir/local-ai-pi-copilot" --config "$config" remember >/dev/null
jq -e '.version == 1 and (.rules | length) == 1 and .rules[0].appId == "org.example.App"' "$test_root/playbook.json" >/dev/null

"$plugin_dir/local-ai-pi-copilot" --config "$config" test-suggestion >/dev/null
"$plugin_dir/local-ai-pi-copilot" --config "$config" dismiss >/dev/null
jq -e 'length == 0' "$test_root/state/suggestion.json" >/dev/null

"$plugin_dir/local-ai-pi-copilot" --config "$config" render-service | grep -Fq 'NoNewPrivileges=yes'
"$plugin_dir/local-ai-pi-copilot" --config "$config" render-service | grep -Fq 'ProtectHome=read-only'
"$plugin_dir/local-ai-pi-copilot" --config "$config" install-service >/dev/null
[[ -f $test_root/units/omarchy-local-ai-pi-copilot.service ]]

"$plugin_dir/local-ai-pi-copilot" --config "$config" status | jq -e '
  .configured and (.enabled | not) and (.active | not) and .privacy.screenshots == false
' >/dev/null

printf '%s\n' '[unknown]' 'value = true' >"$test_root/invalid.toml"
if "$plugin_dir/local-ai-pi-copilot" --config "$test_root/invalid.toml" doctor >/dev/null 2>&1; then
  printf 'doctor unexpectedly accepted unknown config\n' >&2
  exit 1
fi

rg -q 'id: suggestionWindow' "$plugin_dir/Panel.qml"
rg -q 'anchors.bottom: parent.bottom' "$plugin_dir/Panel.qml"
rg -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$plugin_dir/Panel.qml"
rg -q 'mask: Region \{ item: suggestionCard \}' "$plugin_dir/Panel.qml"
rg -q -- '--no-tools' "$plugin_dir/local-ai-pi-copilot"
rg -q -- '--no-skills' "$plugin_dir/local-ai-pi-copilot"
rg -q -- '--no-context-files' "$plugin_dir/local-ai-pi-copilot"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$plugin_dir" >/dev/null
fi

printf 'Local AI Omarchy Pi Copilot checks passed\n'
