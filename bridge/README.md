# Cowork bridge

Use UAI in your browser while Roblox runs your tools and keeps the conversation.
Run both on the same computer. The [Windows desktop app](../desktop/README.md)
detects installed Node.js and offers a verified download if needed. Open the
single **UAI-Bridge-3.2.0-win-x64.exe** download, complete Node setup, click **Start
Cowork**, and load the updated UAI script. The browser opens and Roblox connects
automatically on dedicated port **28791**. No terminal or token copying is needed.

The terminal workflow below needs **Node.js 18 or newer** and has no production
npm dependencies. It retains port 8790 and manual pairing.

Join the [Project UAI Discord](https://discord.gg/9xYyyYuKap) for help, provider
availability updates and new free options. Project UAI Free is the default for
users without a provider; thank you for continuing to use and support Project UAI.

## OpenCode on desktop

The existing direct desktop workaround remains supported. Version 3.2 also adds
an optional native route through an **already installed OpenCode CLI**. Install
[OpenCode Desktop](https://opencode.ai), restart Cowork, and wait for its OpenCode
status to become ready. UAI does not download or package the OpenCode binary.
OpenCode free models are unsupported on mobile; use Project UAI Free or another provider.
The retired OpenCode HTTPS proxy is never used; the proxy supports AgentRouter only.

**OpenCode Go subscriptions use a separate endpoint:**
`https://opencode.ai/inference/go/v1`, with your Go API key. The legacy
`https://opencode.ai/zen/go/v1` route also remains accepted. Go requests use that
endpoint directly and never enter the isolated native free-model connection.
The desktop-only free-model restriction does not apply to Go subscriptions.

The bridge detects OpenCode Desktop's Windows `resources/opencode-cli.exe`, native
`opencode-cli`/`opencode` binaries on PATH, and `~/.opencode/bin`. A custom native
binary may be selected with the absolute `UAI_OPENCODE_BINARY` environment variable.
Shell shims are not executed. `UAI_OPENCODE_DISABLED=1` disables this optional route.
OpenCode's v2 server API is required (verified with CLI 2.0.27).

The bridge starts `serve` privately on a random loopback port with a random Basic
Auth password and isolated configuration/data directories. It never reads the
user's OpenCode account credentials or forwards a provider key to that process.
Only models reported by the native public catalog route through it; paid/custom
models and installations without a ready native backend retain the direct path.
Model discovery uses authenticated `GET /api/opencode/models`; `/api/hello` exposes
`capabilities.opencode = {schema:1, available, state, models}` without CLI credentials.

Each request gets a temporary native session and location. UAI tools are exposed
through a private MCP server, collected after the provider stream completes, and
returned as ordinary tool calls for Roblox to execute. Native desktop actions are
never approved. The native built-in schemas remain visible with ask permissions,
as hiding them causes upstream `FreeTierError`. Text/reasoning previews and image
attachments pass through the native API. Stop interrupts and deletes the session;
bridge shutdown stops the owned CLI and removes its temporary data. Requests keep
their original bridge ID across polling retries. No inference deadline is added.
Usage totals include cached input and reasoning output; cache reads, cache writes,
and reasoning counts remain available separately for UAI's usage accounting.

## Claude Code on desktop (personal use)

If **Claude Code is installed and signed in on this computer**, choose the
**Claude Code (local CLI)** provider in Roblox. It needs no API key: for each
request the bridge runs your own, unmodified `claude` binary, so usage counts
toward your own Claude plan. This is personal, local use with your own sign-in,
as described in Anthropic's
[legal and compliance terms](https://code.claude.com/docs/en/legal-and-compliance).
It is **unavailable on mobile, through the Android companion and through any
relay**, and it is never placed behind Project UAI Free, the proxy or a shared key.

The preset's base URL is `https://claude-code.invalid/v1`. The reserved `.invalid`
host never resolves, so a request that misses the bridge fails at DNS on this
machine. The bridge serves it only to the Roblox game on the same computer: a
loopback peer using the exact `127.0.0.1:<port>` host, with no browser `Origin`,
Fetch Metadata, forwarding header or companion relay marker. Anything else is
refused with an explanation. One Claude Code request runs at a time per bridge;
a second request is refused with a clear message.

The bridge never reads, copies or logs `~/.claude/.credentials.json`, the OS
keychain or `CLAUDE_CODE_OAUTH_TOKEN`, and never offers a sign-in flow. If
`claude auth status` reports you signed out, the provider shows: *Run `claude` in
a terminal and sign in, then restart Cowork.* Only the reported sign-in method and
API provider are kept, for display. The child keeps your own `HOME`,
`USERPROFILE`, `APPDATA` and `CLAUDE_CONFIG_DIR`; only `ANTHROPIC_BASE_URL` and
`ANTHROPIC_CUSTOM_HEADERS` are removed so a stray variable cannot redirect it.

Discovery uses `UAI_CLAUDE_BINARY` (an absolute native binary), then
`~/.local/bin/claude[.exe]` (the native installer), `~/.claude/local/claude`, and
native `claude`/`claude.exe` binaries on PATH. An npm `.cmd`/`.ps1`/shell shim is
never run: the bridge runs the official package's native binary, or its JavaScript
entry with the bridge's Node.js. `UAI_CLAUDE_DISABLED=1` disables this route. At
startup the bridge checks `claude --version`, the required `--help` flags and
`claude auth status --json`; an older version reports that Claude Code needs an
update.

Each request is stateless, like the OpenCode route: Roblox's compacted history is
the conversation of record. The bridge starts `claude -p` with stream-json input
and output, partial messages, `--tools ""` (no host tools), only its private UAI
MCP server (`--strict-mcp-config`, `--allowedTools "mcp__uai__*"`), `dontAsk`
permissions with prompts denied, no slash commands or skills, no session files and
hooks disabled. `--bare` is never used because it ignores subscription sign-in.
The system prompt and MCP configuration are passed as files in an empty per-job
temporary folder, which keeps them within Windows command-line limits and keeps
the MCP bearer secret out of the process list. Text and thinking stream as
previews. Tool calls are returned to Roblox when the model turn stops; the child
is ended before a second turn can start and the MCP calls are never answered. A
request for any non-UAI tool fails and nothing runs. Stop or shutdown ends the
child and removes its folder. Model discovery uses authenticated
`GET /api/claudecode/models` (`sonnet`, `opus`, `haiku`, `fable`; full `claude-`
model IDs also work). `/api/hello` exposes `capabilities.claudeCode = {schema:1,
available, state, models, aliases, version, authMethod, apiProvider, message}`,
where `state` is `missing`, `starting`, `signed-out`, `ready` or `failed`.

Your own Claude Code may still apply your user-level settings and memory files,
such as `~/.claude/CLAUDE.md`. The bridge disables hooks, other MCP servers and
host tools, but it does not move or hide your own configuration.

## Start in three steps

1. **Download and start.** In Roblox, open **UAI → Cowork → Download bridge files**.
   Open a terminal in your executor's workspace folder—the folder containing
   `UAI`—and run:

   ```powershell
   node UAI/bridge/start.txt
   ```

   From a Git checkout instead, open a terminal in the repository folder and run
   `node bridge/server.js`.
2. **Connect Roblox.** The terminal prints a **Token**, a port (normally `8790`),
   and a browser link. Paste the token into **UAI → Cowork**, match the port,
   and turn **Enabled** on.
3. **Open the browser link.** Choose a provider and model, then send a message.
   Keep Roblox and the terminal open while you work. Press `Ctrl+C` in the
   terminal when you want to stop the bridge.

No `npm install` or manual file renaming is needed. The download uses `.txt`
files because some executors block executable file extensions. Node checks their
sizes and Git blob hashes, restores their original names inside the downloaded
package, and starts the bridge. Downloads use one pinned revision and a new
package folder; the launcher changes only after all downloaded files are saved.

After a manual restart, open the **new** browser link and paste the **new** token into
Roblox. To use a different port, append `--port 8791` to the start command and
enter that port in Roblox too.

## Automatic updates

The bridge checks official stable GitHub releases after startup and every 15
minutes, downloads compatible releases and verifies the package and file SHA-256
hashes. It activates updates only when inference, commands, agents and retained
receipts/pictures are idle. Pairing tokens survive automatic worker restarts.
Failed downloads or startup keep a working version. Git checkouts and executor
download packages are never overwritten; updates live in a per-install user cache.

Publish `dist/bridge-release.json` and `dist/uai-bridge-package.json` on the same
official `v3.2.0` or `bridge-v3.2.0` GitHub release. Generate them with
`node tools/build_bridge.js` after reviewing final bridge/web inputs, inspect
the outputs, then run `node tools/build_bridge.js --check` and focused tests.
Later releases must bump `bridge/release.js` and use the matching release tag.
The release builder embeds OpenCode/support helpers into the original permitted
root filenames so installed 3.1 updaters can verify and activate 3.2. Checkout,
executor downloads and desktop payloads retain the separate source modules.

The [desktop app](../desktop/README.md) independently downloads its own release
and applies it on restart. An old 1.0 desktop ZIP needs one manual upgrade first.

## Working in the browser

- **Chat** follows the active Roblox conversation. Use the sidebar to find or
  start conversations; draft text and code files stay with their conversation.
- **Runtime follows the connection.** Successful authenticated bridge contact
  selects Web automatically, with live responses when the provider supports
  streaming. Disconnecting restores Game for subsequent requests. Roblox owns
  conversations and tools in both modes; reconnecting never resends a message.
- **Bridged requests have no overall time limit.** Cowork waits for completion,
  Stop, or a real provider/connection failure. This is permanent, with no timeout
  setting. Individual status polls stay short and reuse the original request ID;
  a stalled poll does not submit the provider request again.
- **Attach text or code** with the paperclip, drag a file onto the composer, or
  paste long text. Large inputs become verified files that the agent can read.
  Limits: 10 MiB per file/input, 16 text files and 16 MiB per draft.
- **Attach pictures** with the image button, paste, or drop. PNG, JPEG and WebP
  are sent as **actual image content** to your selected model; choose one that
  supports vision. Reload the updated game client and restart the bridge first.
  Limits: 8 pictures, 5 MiB each, 20 MiB held by the
  bridge, 4096 × 4096 and 12 megapixels. Animated images are not supported.
- **Stop** cancels the current turn. Closing or refreshing the browser does not.
  If delivery is unclear, use **Check delivery** before sending again.
- **Settings → Browser appearance** offers system, light, dark, and Match Roblox.
  Conversation text scaling keeps sidebar labels compact. Dialogs keep their
  headings and actions available while long forms scroll, and restore focus
  when dismissed. Client animations are permanently enabled; browser system
  reduced-motion preferences still apply to browser transitions.
  Exported conversations include picture metadata, not image bytes. A full
  configuration export includes API keys.

Commands can arrive immediately while Roblox's long poll is waiting. Desktop
polls can wait 18 seconds; touch-only mobile clients request one-second polls
with short request deadlines. Game updates are batched about
every 150 ms, live browser text paints about every 60 ms, and command receipts
are checked every 250 ms. These are batching intervals, not an end-to-end latency
guarantee; executor scheduling and the provider's response time also matter.

## If something is stuck

| What you see | What to do |
| --- | --- |
| `node` is not recognized | Install Node.js 18+, close the terminal, and open a new terminal. |
| The start file cannot be found | Open the terminal in the executor workspace containing `UAI`. Download the files again if `UAI/bridge/start.txt` is missing. |
| Download failed | Retry in Cowork. A failed download keeps the existing launcher; HTTP, file read/write, and folder creation are required. |
| Package verification failed | Download again. Do not edit or rename the downloaded `.txt` files. |
| Roblox is waiting to connect | Keep the terminal open. Check the port, paste its latest token, then enable Cowork. Both must run on this computer. |
| The token no longer works | The bridge may have restarted. Use its latest token and browser link. |
| Live responses are unavailable | Check that Cowork says connected and Web runtime, then check provider SSE support. Non-streaming providers still return a complete reply. |
| A picture is expired or unavailable | Attach it again. Pictures expire after 15 minutes of inactivity and disappear when the bridge stops. |
| The bridge is reconnecting | Keep your draft in the tab and restart/reconnect the bridge. Review the conversation if a delivery receipt was lost. |
| A deadline error appears | Use the highlighted Discord tutorial link. Cowork imposes no overall deadline, but an upstream provider or transport can still fail. |
| Claude Code says to sign in | Run `claude` in a terminal, sign in with Anthropic's own flow, then restart Cowork. The bridge never handles your credentials. |
| Claude Code needs an update | Run `claude update`, then restart Cowork. |
| Claude Code answers one request at a time | Wait for the current reply, or choose another provider for subagents and parallel work. |
| OpenCode reports `FreeTierError` | Keep the direct desktop workaround enabled, or install/update OpenCode Desktop and restart Cowork for the native route. Mobile is unsupported. [Discord help](https://discord.gg/9xYyyYuKap). |

## Development and tests

`server.js` owns authenticated loopback routes, command receipts and browser SSE.
`inference.js` owns provider requests and bounded preview replay. `picture-store.js`
keeps validated image bytes in memory. `launcher.js` restores executor downloads.
`opencode.js` owns the external native server, temporary sessions and MCP handoff;
`claudecode.js` runs the user's own signed-in Claude Code per request with the same
MCP handoff; `native-response.js` shapes both into OpenAI-compatible replies;
`support.js` supplies consistent Discord error help.
`supervisor.js` owns the worker process, token and idle replacement;
`updater.js` validates releases and maintains the isolated cache.
`web/` contains the dependency-free UI, Markdown, previews, pictures, themes and
asynchronous draft storage. Roblox remains authoritative in both runtimes.

All bridge tests live in `tests/`. Shared utilities are in `tests/helpers/` and
synthetic game/image inputs in `tests/fixtures/`. The JPEG/WebP fixtures are real
encoded images; tests generate valid PNG chunks without additional dependencies.

Finish implementation, documentation and test edits before running verification:

```powershell
luajit tools/bundle.lua --native
node tools/build_site.js
node --test bridge/tests/opencode-native.test.js bridge/tests/opencode.test.js bridge/tests/claudecode.test.js bridge/tests/desktop.test.js bridge/tests/security.test.js bridge/tests/streaming.test.js bridge/tests/updater.test.js
luajit test/web_runtime.lua
luajit test/bridge_install.lua
luajit test/claude_code_bridge.lua
```

For real browser checks, install Playwright **outside this repository**, including
its Chromium browser. Set `PLAYWRIGHT_MODULE` to that package's absolute directory
if it is not on the normal module path. Optionally set `UAI_SCREENSHOTS` to an
output directory, then run:

```powershell
node bridge/tests/run.js --browser-only
```

The browser suites cover navigation, forms, streaming, picture ownership/replay,
upload cancellation, receipt races, full drafts, themes, drawer focus, token
recovery, CSP, reduced motion, and 320–1440px layouts. The UI audit suite also checks
short screens with full drafts, long task lists and model names, live question and
selection updates, dialog errors, keyboard focus, contrast, and forced colors.
Inspect the saved screenshots as well as checking geometry. These fixtures do not
replace a live executor check. See the [UI audit](UI_AUDIT.md) for the findings.
The [3.2.0 verification record](../docs/TESTING_3.2.0.md) records the current
bridge release checks; the entire native suite is not part of this pass.

Protocol remains version 2. `/api/hello` advertises optional picture and normalized
stream capabilities. `--legacy` disables pictures and uses compatibility delta
frames. Raw provider response bodies remain separate from browser preview rings;
oversized or truncated responses fail explicitly. Picture capability v2 uses
`provider-image-content`; game state advertises `imageInput = true`. The bridge
rejects image sends to older clients instead of substituting text markers.

Image sends carry compact, conversation-scoped references into model context.
At inference dispatch, the bridge expands them to Chat Completions `image_url`
data URLs, Anthropic base64 `image` blocks or Responses `input_image` blocks.
Image-bearing requests use the relay in either
runtime. Tokens, image bytes, and provider keys are never added to browser event
frames. A missing current image fails explicitly; expired earlier images become
a clear unavailable-image text block so a later text-only turn can continue.
Request retries use their original ID before resolving images, so expiry cannot
cause a second provider dispatch. Active upload bodies and provider bodies are
bounded separately. Model vision support remains provider-specific.

The bridge binds to loopback, rotates its bearer token on restart,
checks browser origins and serves local assets under a same-origin CSP. Desktop
mode adds a native-only local discovery route with exact Host checking, a custom
POST header, browser-header rejection and no CORS. See the desktop guide for its
local-program trust boundary and launcher lifecycle tests.
