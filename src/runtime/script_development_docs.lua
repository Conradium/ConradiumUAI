-- Generated from docs/SCRIPT_DEVELOPMENT.md by tools/build_script_docs.lua; edit the Markdown.
return function(env)
	return {
		url = "https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md",
		order = {
			"quickstart",
			"task_routing",
			"paths_and_tool_calls",
			"inspection",
			"luau",
			"execution_and_cleanup",
			"ui_scripts",
			"debugging",
			"projects",
			"editor_and_actions",
			"verification",
			"tool_reference",
			"maintaining_the_guide",
		},
		titles = {
			["quickstart"] = "Quickstart",
			["task_routing"] = "Task routing",
			["paths_and_tool_calls"] = "Paths and tool calls",
			["inspection"] = "Inspection",
			["luau"] = "Luau",
			["execution_and_cleanup"] = "Execution and cleanup",
			["ui_scripts"] = "UI scripts",
			["debugging"] = "Debugging",
			["projects"] = "Projects",
			["editor_and_actions"] = "Editor and actions",
			["verification"] = "Verification",
			["tool_reference"] = "Tool reference",
			["maintaining_the_guide"] = "Maintaining the guide",
		},
		sections = {
			["quickstart"] = [=[
## Quickstart

Turn a clear scripting request into a small working result:

1. Identify the behavior, source destination, startup action and observable
   success. Follow the user's scope and the permission layer; do not add a second
   approval question for authorized work.
2. Use the **Current game files** path already supplied in the environment. For an
   existing file, read its relevant source. For a selected Code document, use
   `code_read` so unsaved edits are included. For a new self-contained script using
   standard services, begin authoring; game-wide discovery is unnecessary.
   When only a filename or extension is known, use `file_find` with a narrow path
   and filename glob; it discovers reusable paths without reading file contents.
3. Inspect only unknown facts the implementation depends on: a target's exact
   path/class, a property, an existing callback or a remote's observed arguments.
   Batch independent reads. Do not guess a remote, module API or executor function.
4. Write complete source with `file_write`; its parent folders are created for
   you. Use `file_edit` or `file_edit_many` for a targeted existing-file change.
   Large new files use sequential `file_write` then `file_append` calls. Keep each
   call comfortably within the response budget and use complete JSON.
5. Review the actual changed source for syntax, API use, lifetime and the user's
   requirement. Compile the saved path with `check_luau`. A successful compile
   proves syntax only. Fix the specific diagnostic before trying execution.
6. When authorized, use `run_luau` on that same path. Inspect its status and output.
   Verify the requested effect with a targeted observation or an explicit returned
   value. Repair the smallest relevant cause; do not blindly repeat a timeout.
7. Report the exact saved path, what was verified and what remains unverified.
   A working local change does not prove server replication. A saved or compiled
   script is not automatically a tested script. Stop when the requested work is done.

For example, if the environment's actual current path were
`files/Example_12345`, these would be three **successive** tool calls:

```json
{"path":"files/Example_12345/hello.lua","content":"local player = game:GetService(\"Players\").LocalPlayer\nassert(player, \"Local player is unavailable\")\nreturn { player = player.Name, placeId = game.PlaceId }\n"}
```

Call `file_write` with that object. Review the source, then call `check_luau`:

```json
{"path":"files/Example_12345/hello.lua"}
```

After compilation succeeds, call `run_luau` with the same object. Substitute the
real environment path; `Example_12345` is an example, not a folder to invent.
The normal deadline is 10 seconds; 1–60 seconds is supported when needed.

Choose `inspection` for unknown game behavior, `ui_scripts` for an interface,
`execution_and_cleanup` for callbacks or persistent effects, `debugging` for a
failure, `editor_and_actions` for a live Code draft, or `projects` for multiple
modules. Follow a selected section's `nextOffset` with `offset` until `eof`.
]=],
			["task_routing"] = [=[
## Task routing

Choose the shortest workflow that can satisfy the request:

| Task | Start here | Add only when needed |
| --- | --- | --- |
| New simple utility using known Roblox services | Author one saved script | One syntax check and one authorized execution |
| Change a named saved script | Read that file or search within it | Exact edits and a focused behavior check |
| Locate source by filename or extension | `file_find` under the current game directory | `file_read_many` for selected returned paths |
| Fix the user's open Code document | `code_tabs`, then `code_read` | Revision-guarded edit and `code_run` |
| Add controls to a standalone script | `ui_library_docs` Quickstart, Controls and Lifecycle | Other UI sections for the actual controls/layout |
| Understand one game behavior | Narrow instance/script query under the relevant root | Read selected source or observe the relevant remote |
| Build several mutually dependent modules | `project_map` or `project_scaffold` | Reviewed patch, deterministic build, relevant project tests |
| Inspect a source attachment | `file_read` or `file_read_many` on its `pastes/...` reference | Read the end too; it may contain the user's request |
| Make a persistent chat responder | Existing chat tools when offered | Use their IDs and stop controls, not a polling script |

Tool availability matters more than a familiar tool name. The OpenCode provider
may include `bash`, `read`, `edit`, `glob`, `grep` and `list` solely as required
compatibility declarations. They are not local shell/filesystem implementations
unless the actual client explicitly supplies those tools. Use `file_read`,
`file_find`, `file_search`, `file_list`, `file_edit` and the other real offered tools with their
own schemas. Do not send shell commands to `run_luau`. If an unknown-tool response
suggests an available tool, construct a new call using that tool's schema; changing
the name while retaining another API's arguments is not a repair.

For substantial work, a task list can track a few concrete outcomes. Delegate an
independent investigation only when it saves work. Give each worker an exact target,
scope and deliverable; do not have multiple workers edit the same file or mutate
the same runtime state. The default read subagent cannot implement a change. Use
an appropriate available preset when changes are part of its authorized task.
Collect relevant reports before claiming the delegated work is complete.

Project tests accept `modules` containing declared test IDs and `filter` containing
a case-name substring. Run the selection relevant to the change, inspect its
pass/fail and skipped counts, and expand only when the change requires broader
coverage. Zero matching cases is a failure. Unchanged sources reuse bounded
lexical and syntax caches; saved files and dependencies are still rechecked.

For external documentation, `web_read` returns a `pageId` and `nextOffset`. Continue
with `page_id` and `offset` to read the same retained text without another HTTP
request. These snapshots expire after five minutes or eviction; refetch an expired
URL when needed. `skills_list` can filter installed names, filenames and descriptions
with `query` before reading only relevant skill bodies.

Do not turn uncertainty into broad refusals. A missing API, a server-owned state
or a denied tool is a specific limit. Complete the useful authorized parts that
are available and describe that limit accurately. Never route around a permission
decision through another tool, remote or script.
]=],
			["paths_and_tool_calls"] = [=[
## Paths and tool calls

There are different source identities. Keep them separate:

| Identity | Meaning | Correct access |
| --- | --- | --- |
| `files/.../feature.lua` | Saved workspace source | File tools, `check_luau`, `run_luau` |
| `pastes/...` | Saved input attachment | File reads and source compile/run when appropriate |
| Code document ID plus revision | Live editor draft | `code_read`, `code_edit`, `code_write`, `code_run` |
| `sourceId` | Retained inspected/decompiled snapshot | `script_source` with `source_id`, or `code_read` |
| Instance ID or exact instance path | A live Roblox object | Instance/source/explorer tools |
| Project module ID | Key declared in `uai.project.json` | Project-local `require("id")` |

Reuse returned `files/...` and `pastes/...` paths unchanged. Do not prepend `UAI/`
or another `files/`; a returned `files/files/...` may be a real legacy directory.
Preserve existing Unicode and whitespace exactly. Choose portable ASCII names for
new files and use the game's supplied path, not a reconstructed display name.
Keep inspected/dumped source in the supplied game `dump/` directory; do not confuse
it with a new editable implementation. On a path failure, inspect the parent once
and use the returned canonical path. Repeating guessed slash/prefix variants is
usually wasted work.

Use JSON objects as tool arguments. Tool argument strings contain escaped source
text, not Markdown fences. Within JSON, newline is `\n`, a quote is `\"`, and a
backslash is `\\`. Within Lua source, use Lua syntax: `nil`, `true`, `false` and
Lua tables. JSON `null` is not a Lua value. Do not double-escape newlines so the
saved file literally contains backslash followed by `n` outside a string.

Read two known slices with `file_read_many`:

```json
{"reads":[{"path":"files/Example_12345/main.lua","offset":1,"limit":1800},{"path":"files/Example_12345/settings.lua","offset":1,"limit":900}]}
```

The field is `reads`, an array of objects with `path`; it is not `files` or a
string array. There are up to 12 reads. Each slice has its own continuation;
`nextIndex` means resume the original request list using `start_index`. It does
not mean a prior slice reached its end. Continue individual source slices from
their `nextOffset` when the remaining source is needed.

Find a literal within a known directory using `file_search`:

```json
{"path":"files/Example_12345","query":"CharacterAdded","glob":"*.lua","limit":8}
```

`query` is a single-line literal, not regex. `glob` matches the filename; put the
directory in `path`. Continue using the returned `nextCursor` as `cursor` with the
same query/path/options. Search may omit oversized/binary files or stop at an
inventory/read limit; incomplete search is not proof that code does not exist.

Apply related exact changes in one file using `file_edit_many`:

```json
{"path":"files/Example_12345/main.lua","edits":[{"old_text":"local INTERVAL = 1","new_text":"local INTERVAL = 0.25"},{"old_text":"print(\"debug\")\n","new_text":""}]}
```

Read before editing. Include enough unchanged surrounding text to identify a
unique match; whitespace matters. Each edit sees the previous edit's proposed
result. All edits validate before one write. Empty `new_text` deletes. Use
`replace_all:true` only when every occurrence should change. A stale/ambiguous
edit needs a fresh relevant read, not a forced whole-file overwrite.

Offsets are one-based UTF-8 bytes. A file slice, search cursor, diff-row offset
and Code line range are not interchangeable. Trust the returned continuation
rather than calculating one from the displayed character count. A compacted
excerpt is evidence, not necessarily complete source suitable for replacement.
]=],
			["inspection"] = [=[
## Inspection

Inspect only what the proposed script needs to know. If the task is to make an
anchored local Part, no decompile, remote capture or full-game map is necessary.
If the task depends on a game's door controller, inspect the nearby door model,
its attributes and the relevant controller; do not start by dumping every script.

For a targeted query, `instance_query` accepts `root`, `name`, `class`, `tag`,
`properties`, `attributes`, `limit` and `offset`. For example:

```json
{"root":"Workspace.Doors","class":"BasePart","properties":["Name","Anchored","CanCollide"],"attributes":["Locked"],"limit":8}
```

Use an observed root; the example root is not evidence that this game has it.
For known targets, `instance_get_many` accepts `paths` plus selected `properties`
and `attributes`. Avoid reading Source as a bulk property: use the dedicated
source tool for readable output and provenance. Prefer returned IDs when names
are ambiguous; quoted bracket segments preserve punctuation in instance paths.
Re-resolve expired IDs rather than guessing another object with a similar name.

`script_list` accepts a narrow `root`, optional `kind` and a cursor. The native
implementation pages a bounded query. Follow its returned cursor only if more
results matter. Once the relevant script is identified, call `script_source`
with exactly one of `instance_id`, `path` or a retained `source_id`. A source
page returns `sourceId`, provenance and continuation offsets. Read later pages
using the same `source_id` and `offset`; this keeps a single snapshot instead of
repeatedly decompiling. `refresh:true` is an explicit request for fresh inspection,
not the default for every page.

Source inspection tries host-readable source and supported decompilation paths.
When the host decompiler is missing or fails, the bundled luacid fallback and
then ByteFall may be tried if their prerequisites are available. Native decompile
and bytecode-based fallbacks have different capabilities. Failed service messages
are diagnostics, not executable source. Do not copy a decompiler failure comment
into a script and claim the code was recovered. Do not assume that every live
Script or ModuleScript is readable or that client-visible source includes the
server implementation.

External luacid/ByteFall fallbacks send the selected script's bytecode to their
decompilation service. A native decompiler can work without a separately exposed
bytecode reader; the external fallbacks require bytecode and HTTP access. Forced
`decompile:true` skips the ordinary Source read. Host-readable empty Source is a
valid empty snapshot; empty/comment-only or malformed decompiler output is a
failed recovery, so the next available fallback is tried. Source snapshots cap at
2 MiB per snapshot, with eight snapshots/8 MiB retained for up to five minutes
unless pinned by an open view. At most four workers run, with a 15-second waiter
deadline. Expired waits do not forcibly close a native continuation.

Retained source has a bounded lifetime and size. Snapshots can expire, source can
change, and results arriving after Stop are discarded. Reuse a valid snapshot;
refresh only when it is expired/stale or current behavior requires new evidence.
An inspected document is read-only. Extract an editable implementation before
running or proposing changes; inspecting source does not write back into a live
game script. Do not retry the same failed decompile repeatedly or manually fetch
fallback services that the source layer already tried.

For a remote-dependent task, first establish the relevant remote and its actual
argument structure. Opening captures or reading remote metadata sends no traffic.
Capture only the required target/scope with a bounded stop condition. Keep incoming
events separate from outgoing actions; replay sends traffic and needs authorization.
Prefer the packed typed argument format when exact nil positions and Roblox types
matter. Legacy `vec3:`/`vector3:`/`number:` prefixes convert values; prefix a literal
string with `string:` when its text would otherwise be interpreted as a type.
Do not infer a server command solely from a suggestive remote name.
]=],
			["luau"] = [=[
## Luau

Authored user scripts execute as Roblox Luau when the host exposes its compiler.
The repository's own client modules use a LuaJIT-compatible authoring convention;
that convention does not require every user script to be an `env` factory or ban
normal native Luau features. Still prefer simple, explicit code over clever syntax
when it makes a small script easier to inspect and repair.

- Get services with `game:GetService("Players")` and
  `game:GetService("RunService")`. A variable called `Players` is not created
  automatically. `Players.LocalPlayer` exists only in a client context.
- Use `object:Method(...)` for Roblox instance methods and `module.function(...)`
  for plain functions unless that module's API explicitly uses a receiver.
  Confusing dot and colon calls shifts every argument.
- Arrays start at one. `nil` removes a table entry. Use an explicit count when
  trailing nil arguments matter; `#table` is not a reliable count for sparse data.
- Use `Vector3.new(x, y, z)`, `CFrame.new(...)`, `Color3.fromRGB(r, g, b)` and real
  Enum members. Do not assign a JSON object or string where Roblox expects a
  typed value. Clamp/validate user inputs before applying them.
- Names can contain spaces and punctuation: `object["Door Control"]` or
  `FindFirstChild("Door Control")` is different from `object.Door Control`.
  Duplicate child names need an unambiguous observed target.
- `FindFirstChild` can return nil. `WaitForChild(name, timeout)` can also return
  nil after its timeout. Use a bounded wait only when the object should appear;
  assert or report a useful missing-object error instead of indexing nil.
- `player.Character` can be absent or replaced. Resolve the current character
  when acting, and use an owned `CharacterAdded` connection for respawn behavior.
  Do not keep one Humanoid reference forever and assume it remains current.
- Check the actual class before relying on class-specific members. An object
  named "Part" can be a Model; a Model does not have `Position`.
- Avoid writing global names for ordinary locals. A shared global is appropriate
  only for an intentional rerun/cleanup handle with a unique script-specific key.
- Keep configuration data separate from executable expressions. Never interpolate
  user text into source when the operation can receive it as a string/number/table.
- Use `task.wait()` to pace finite loops. Heavy per-frame work should be bounded,
  and event-driven updates should avoid rescanning the full game on every frame.

This complete local example creates or updates only a marker it can identify as
its own. It uses no UI and needs no unknown game APIs:

```lua
local workspace = game:GetService("Workspace")
local name = "UAIExampleMarker"
local marker = workspace:FindFirstChild(name)
if marker then
	assert(marker:IsA("Part") and marker:GetAttribute("UAIExampleMarker") == true,
		"The marker name is already used by another object")
else
	marker = Instance.new("Part")
	marker.Name = name
	marker:SetAttribute("UAIExampleMarker", true)
end
marker.Anchored = true
marker.CanCollide = false
marker.Size = Vector3.new(2, 2, 2)
marker.Position = Vector3.new(0, 10, 0)
marker.Color = Color3.fromRGB(255, 120, 80)
marker.Parent = workspace
return { path = marker:GetFullName(), anchored = marker.Anchored, localEffect = true }
```

Adapt the position/name only to the request. Do not use an example as permission
to add an unrelated marker. `check_luau` cannot establish whether an object exists,
whether the host permits an API or whether a local change will replicate.
]=],
			["execution_and_cleanup"] = [=[
## Execution and cleanup

`run_luau` accepts exactly one of `code` or `path`, plus optional `timeout`.
Use `path` after writing source; it avoids retransmitting the script and executes
the saved bytes. Inline source is useful for a tiny focused observation. The
default deadline is 10 seconds, and the allowed range is 1–60 seconds. Increase it
for a genuinely longer finite operation, not to hide a loop or an unresolved error.

The managed engine captures `print`, `warn`, return values and useful table
contents. Keep output small and explicit: counts, exact paths, key observed
values and the relevant failure. Prefer one summary after a loop to thousands of
prints. Captured output is bounded; omission metadata means the model did not see
everything. Returning a UI table or a graph of Instances is less useful than
returning a small readiness/status record.

Functions started using the run's `task.spawn`, `task.defer` and `task.delay`
share its deadline. The run waits for them. An infinite spawned loop does not
become an independent background feature just because the outer function returned.
Use finite managed tasks for setup/checks. For persistent script features, register
event connections with an explicit owner and cleanup handle; for a UI feature,
that owner is normally the library window. Use existing persistent automation
tools when they already implement the requested lifetime.

Stop is cooperative. It does not undo property changes, remove every object,
revert files, cancel a dispatched server effect or guarantee interruption of a
native function. Dynamic `loadstring` chunks and Roblox/executor continuations can
run outside the lexical loop guards. Native callbacks may complete later, so do
not close their coroutines or repeat an uncertain remote dispatch. A timeout with
unknown outcome requires observation before considering another execution.

Persistent resources need ownership:

| Resource | Required lifetime handling |
| --- | --- |
| Service/instance connection | Store it and disconnect it during cleanup |
| Owned Part/Folder/Highlight | Destroy only that owned object during cleanup |
| Temporary property override | Save the observed original; restore only if the object is still valid and restoration is appropriate |
| Delayed result | Check an alive flag/generation after yielding before applying it |
| Script rerun | Release the earlier instance of that same script, not unrelated UI or game objects |
| UI script resources | Register with `window:Give` or `window:OnDestroy` |

For a finite temporary listener, disconnect even when the wait/body raises:

```lua
local runService = game:GetService("RunService")
local frames = 0
local connection = runService.Heartbeat:Connect(function()
	frames = frames + 1
end)
local ok, problem = pcall(function()
	task.wait(0.25)
end)
connection:Disconnect()
if not ok then error(problem, 0) end
return { framesObserved = frames }
```

Do not wrap the entire program in `pcall` and discard the error. If cleanup is
needed, preserve and rethrow/report the original failure after cleanup. If a
signal callback outlives the initial run, it must report failures through its own
visible status or diagnostic path; the completed run cannot capture future output.
]=],
			["ui_scripts"] = [=[
## UI scripts

New script-owned interfaces use **Project UAI UI LIB**. Read `ui_library_docs`
sections `quickstart`, `controls` and `lifecycle`, including continuations, before
authoring. This section explains integration choices; the library tool remains
the authoritative API reference. Read `layout`, `configuration`, `recipes` or
`runtime_integration` only when needed.

The canonical standalone bundle is:

`https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua`

Load it once at the script entry point, then pass the API to any application
modules. Scripts declare tabs, sections, values and domain callbacks. The library
owns ScreenGui/control creation, colors/fonts/spacing, drag/resize/input, local
profile/headshot and the fixed `Project UAI | UI LIB.` attribution. Navigation and
actions have text-only labels. Do not add icon marks, third-party UI loaders,
arbitrary GUI instances or custom styling through exposed GUI handles. Missing
reusable controls belong in the shared library. An explicit request to modify an
existing custom UI may preserve that interface; the agent client's `src/ui` is a
separate established application.

This complete example creates a window and an owned domain folder. The marker is
created only when the user presses the action. All GUI construction stays in the
library, and closing/replacing the window releases the folder:

```lua
local UI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"
))()
local window = UI:CreateWindow({ Id = "example-marker-tools", Title = "Marker tools" })
local tab = window:Tab({ Id = "main", Title = "Main" })
local section = tab:Section({ Title = "Marker" })
local height = section:Slider({
	Id = "marker-height", Text = "Height", Min = 2, Max = 30, Step = 1, Default = 10,
})
local owned = Instance.new("Folder")
owned.Name = "UAIExampleMarkers"
owned.Parent = game:GetService("Workspace")
window:Give(owned)
local marker
section:Button({
	Id = "place-marker", Text = "Place marker", ActionText = "Place",
	Callback = function()
		if not window.Alive then return end
		if not marker or not marker.Parent then
			marker = Instance.new("Part")
			marker.Name = "Marker"
			marker.Anchored = true
			marker.CanCollide = false
			marker.Parent = owned
		end
		marker.Position = Vector3.new(0, height:Get(), 0)
		window:Notify({ Title = "Marker placed", Content = "Created on this client.", Kind = "Success" })
	end,
})
return { windowId = "example-marker-tools", ready = window.Alive }
```

Use stable, unique window and control IDs. Reusing the same window Id replaces
the earlier window and runs its cleanup even when the script loads a fresh UI
bundle. Different IDs coexist. Never delete every ScreenGui or every object whose
name contains a broad keyword as a rerun strategy.

Construction and configuration import are silent by default. A Toggle's Default
does not execute its callback. If the product should start enabled, explicitly
apply the initial domain value after constructing the controls; do not rely on a
callback that did not run. Use `control:Get()` for values and `control:Set(value,
true)` when synchronizing without re-triggering behavior.

Register event connections as `window:Give(signal:Connect(callback))`. Use one
`window:OnDestroy` cleanup for dependent restoration steps. Check `window.Alive`
and a request generation after asynchronous work. Hide/Minimize preserve domain
state and subscriptions; Destroy releases them. Buttons already own their finite
callback tasks. Do not install an indefinite polling worker in a button callback.
Report download/compile failures plainly; do not silently switch UI libraries.
]=],
			["debugging"] = [=[
## Debugging

Read the first meaningful diagnostic and the execution status before changing
source. The final line of a stack trace may be an internal wrapper, not the user
error. Preserve source paths, line numbers, returned status and nearby source as
evidence. Use the smallest repair that explains the observed failure.

| Result | Interpret it | Next useful action |
| --- | --- | --- |
| Unknown tool | The name is not implemented/offered | Use a suggested real tool with its schema; inspect OpenCode compatibility guidance |
| Invalid/truncated JSON | Arguments never formed a complete call | Resend a smaller complete object; split large writes sequentially |
| Source/path error | The intended source was not loaded | List the exact parent once, read the returned path or fix source arguments |
| Compile error | The compiler rejected syntax | Read that source region, correct syntax, compile again |
| Runtime error | Code started and raised | Inspect the failing value/API and any already applied effects |
| No printed output | Nothing called captured print/warn before the result | Read the status and returns; silence alone is not failure |
| Timeout/aborted | Managed work stopped cooperatively; native work may remain | Inspect outcome; do not automatically re-dispatch the same mutation |
| Missing capability | This host cannot supply a required primitive | Use an available supported operation or report the specific limitation once |
| Permission denied | Work was not authorized by current policy/user choice | Respect it and continue other allowed work |
| Approval timed out | No decision arrived before the deadline | Report timeout accurately; do not claim the user declined |
| Stale revision/hash/ID | The target changed since inspection | Read the current target and rebuild the intended change |
| Incomplete scan/source/output | Only part of the evidence is present | Read the returned page/retained detail or narrow the query |

For `attempt to index nil`, identify which expression was nil. A root Part,
character, player or service name should be verified specifically; adding broad
`if object then` wrappers that silently skip the requested behavior is not a fix.
For an invalid member, confirm the object's class and documented member spelling.
For a method argument error, check dot/colon use and the actual typed value.

For an error without printed output, add a few focused checkpoints around the
suspected operation and return relevant types/IDs. Do not scatter hundreds of
prints or replace every error with a generic success string. Preserve errors
from nested `pcall` calls. A numeric or table error is still a failure; convert it
to a useful bounded diagnostic rather than assuming it is a successful return.

After a fix, review it first. Recompile the changed source, then rerun only the
needed check if the prior outcome permits safe execution. Do not repeat unrelated
passing checks. If the same failure persists twice, use new evidence or a different
approach. Keep the user's working draft and prior successful behavior intact.

Token-limited batches are rejected without executing their calls; they do not
count as repeated actions. A smaller complete call can proceed. An ordinary
already-executed repeated call is different: changing whitespace or IDs to evade
the repeat breaker does not resolve its underlying problem.
]=],
			["projects"] = [=[
## Projects

Use projects for multiple real modules or coordinated changes, not as compulsory
setup for a small script. A project manifest explicitly declares module IDs,
relative source files, entry and tests. There is no inferred package manager or
directory-wide module discovery. Read `docs/SCRIPT_PROJECTS.md` in the repository
for the complete public contract.

```json
{"version":1,"entry":"main","modules":{"main":"main.lua","settings":"settings.lua","tests/settings":"tests/settings.lua"},"tests":["tests/settings"]}
```

`require("settings")` resolves a declared project ID. It does not mean a Roblox
Instance or asset ID, and project modules do not get a real ModuleScript `script`
identity. The loader caches module values, preserves false, converts a nil return
to true, and detects active cycles. Keep module initialization free of avoidable
side effects, especially for modules imported by tests.

For a new project, `project_scaffold` with `directory` stages a starter and returns
a `patchId` plus manifest path. It does not write files yet. Inspect with
`project_patch_read` using `patch_id`, then `project_patch_apply`. For an existing
project, `project_map` with `manifest` returns source hashes, outlines, imports and
test IDs. Read the source needed to understand a change; an outline is not a body.

`project_patch` stages `operations`, each naming a `path` and either full
`content` or exact `edits`. Existing files require the observed `expected_hash`;
new files require `create:true`. Read every proposed file, then apply. Writes are
verified one by one, not atomic. Partial failure requires inspecting the returned
recovery state. Do not force an old proposal over external changes or unsaved
Code drafts. `project_patch_restore` conditionally restores only matching
recorded file state; it does not undo native game effects.

Review source, then `script_analyze` with exactly one of `path` or `manifest` for
compiler diagnostics and literal dependency checks. It does not provide Luau
type inference or API validation. For a bundle, `project_build` needs `manifest`
and an `output` ending in `.lua`; replacing output requires its observed
`expected_hash`. Inspect the generated output/source locations before verification.
Building never executes the entry.

`script_test` accepts `manifest`, optional JSON `fixtures` and optional `timeout`.
It executes that manifest's declared test modules. There is no per-case selector
argument: do not invent `test`, `filter` or `cases` fields. Keep a manifest's tests
relevant to its project, and do not invoke unrelated project test runs. Example
test module:

```lua
local settings = require("settings")
return {
	defaults = function(t, fixtures)
		t.equal(settings.name, fixtures.expectedName)
		t.truthy(settings.enabled)
	end,
}
```

Assertions use dots: `t.equal(actual, expected, message?)`, `t.truthy(value,
message?)`, `t.raises(callback, literalSubstring?)`. Equality is ordinary Lua
equality, not deep comparison. Each case gets fresh module caches and copied
fixtures, while native client state is shared. Test setup must not assume an
isolated process. Invalid exports are reported per module; reaching 100 cases
marks the run incomplete. Read both failures and completeness before saying all
tests passed.

Bounds include 64 modules, 16 test modules, 256,000 bytes per source/editable
bundle, 1 MiB project source, and 32,000 bytes for manifests/fixtures. In-memory
patches expire and do not survive reload. Read retained large result details with
`workspace_result_read`; do not treat a clipped summary as the whole patch.
]=],
			["editor_and_actions"] = [=[
## Editor and actions

When the user is working in Code, the live document is the source of truth. A
saved filesystem file can lag behind their unsaved edits. Start with `code_tabs`
to identify `documentId`, current `revision`, active/open IDs and read-only state.
Use `code_read` with `document_id`. Read selected line ranges using `start` and
`count`, or bytes using `offset` and `limit`; they are different coordinate systems.

To replace a line range, `code_edit` needs `document_id`, inclusive `start` and
`finish`, replacement `code` and `expected_revision`. To replace most source,
`code_write` needs `code` and the existing `document_id`/`expected_revision`; use
`new:true` and `name` for a new document. A stale response means read the current
draft and reconcile the change. Never omit the revision to overwrite someone's
concurrent edit. Updating source does not select or execute it.

For a reviewable candidate, `code_propose` needs `document_id`,
`expected_revision`, `code` and optional `name`. It stores a proposal without
applying it. `code_versions` lists source checkpoints and proposals. Source history
and native TextBox Undo differ from the Game changes log; restoring source does
not undo a previously executed script.

`code_run` needs `document_id` and `expected_revision`, with optional `timeout`.
It runs the identified source snapshot and rejects source changed during approval.
Read-only inspected/decompiled documents must first be extracted into an editable
document. Do not pass a document ID as `run_luau.path` or copy an old saved version
into the live draft merely to make it executable.

Saved actions hold executable source snapshots, not live links to a document.
`code_action_save` requires `document_id`, `name` and `source_revision`, with
optional typed `inputs`. Updating an action also needs its `action_id` and
`expected_revision`. Read the action with `code_action_read`; source is available
with `section:"source"`. Then `code_action_run` needs `action_id`,
`expected_revision`, optional `inputs` and `timeout`. Inputs arrive as data:

```lua
local inputs = ...
assert(type(inputs) == "table", "Action inputs are missing")
return { selectedAmount = inputs.amount }
```

Do not interpolate those values into executable source. Do not assume editing
the original document updates an existing saved action. Review and update the
action snapshot explicitly when that is the user's intent.
]=],
			["verification"] = [=[
## Verification

Pick checks that answer a concrete uncertainty. A simple constant or display-text
edit does not require a new test harness or the full project suite. A source
compiler check is cheap and useful after source changes; actual behavior needs
one focused execution or observation when authorized.

| Claim | Evidence needed |
| --- | --- |
| Source saved | Successful file/document write and exact returned path/revision |
| Syntax valid | Successful host compilation of that source |
| Initialization completed | Execution completed, with relevant readiness/error output |
| A local property changed | Read back the target's current property |
| A UI callback works | Exercise that callback and observe its domain result |
| Cleanup works | Close/replace the owned feature and verify its resources are gone |
| A remote succeeded | Its observed result or game state, not just the fact a call was sent |
| Behavior survives respawn | Exercise the new character path |
| Native mobile layout/input works | Observe it on the target Roblox device/host |

Review changes before checks. For a project, review inputs, build, inspect the
generated output, then test. After fixing a failure, review the fix and rerun only
affected checks. Preserve useful successful evidence instead of restarting an
entire workflow each time. Keep pending native/live-provider verification
explicitly pending; offline mocks cannot prove rendering, actual executor input,
server authority or model quality.

For a long-lived UI or event feature, verify three separate outcomes: setup
completes promptly, a representative callback works, and explicit teardown stops
its owned behavior. Re-running the entire setup repeatedly without cleanup can
hide bugs behind duplicate listeners. If initialization creates a window but the
button's domain behavior was not exercised, say so.

Finish with a short useful report: the saved path/document, implemented behavior,
the exact kind of verification performed, and any real remaining limit. Do not
paste the whole source again when the user already has the saved artifact unless
they asked for it. Do not say "fully tested" based only on syntax or "server-side"
based on a local observation.
]=],
			["tool_reference"] = [=[
## Tool reference

This table is an argument reminder, not permission to use an absent tool. The
offered schema remains authoritative.

| Tool | Essential fields | Important distinction |
| --- | --- | --- |
| `scripting_docs` | Optional `section`, `offset`, `limit` | Offline reference; `index` lists available sections |
| `file_list` | Optional `path`, `offset`, `limit` | Returns reusable canonical paths |
| `file_read` | `path`; optional `offset`, `limit` | UTF-8 byte pages |
| `file_read_many` | `reads:[{path,offset?,limit?}]`; optional `start_index` | Per-slice pagination plus request-list pagination |
| `file_search` | `query`; optional `path`, `glob`, `cursor`, `limit` | Literal search, not regex |
| `file_write` / `file_append` | `path`, `content` | Create/replace versus append; sequential on one file |
| `file_edit` | `path`, `old_text`, `new_text`; optional `replace_all` | Exact observed source, unique by default |
| `file_edit_many` | `path`, `edits:[{old_text,new_text,replace_all?}]` | Ordered edits, one validated write |
| `check_luau` | Exactly one of `path` or `code` | Compiles only |
| `run_luau` | Exactly one of `path` or `code`; optional `timeout` | Managed execution; 10 seconds by default |
| `script_list` | Optional `root`, `kind`, `cursor`, `limit` | Narrow instance/source discovery |
| `script_source` | One of `instance_id`, `path`, `source_id`; optional `offset`, `limit`, `refresh`, `decompile` | Inspect once, page the same snapshot |
| `script_analyze` | Exactly one of `path` or `manifest` | Compiler and lexical/dependency checks |
| `script_test` | `manifest`; optional `fixtures`, `timeout` | Executes declared test modules, no case-filter argument |
| `project_map` | `manifest` | Saved sources and observed hashes |
| `project_build` | `manifest`, `output`; `expected_hash` for replacement | Compile/export; does not run entry |
| `code_read` | `document_id`; optional `start`, `count`, `offset`, `limit` | Reads current editor source and revision |
| `code_edit` | `document_id`, `start`, `finish`, `code`, `expected_revision` | Inclusive line edit against a live revision |
| `code_run` | `document_id`, `expected_revision`; optional `timeout` | Executes that document snapshot |
| `ui_library_docs` | `section`; optional `offset`, `limit` | Read required UI sections before authoring |
| `workspace_result_read` | `result_id`; optional `path`, `section`, `offset` | Retained native result details, not a filesystem path |

Source/guide pages use `nextOffset`; queries may use a cursor; batch lists may use
`nextIndex`. Always use the continuation the actual result supplies. Separate
independent tool calls from dependencies: writing, reading its revision, compiling
and executing the same source form a sequence, not one parallel batch.
]=],
			["maintaining_the_guide"] = [=[
## Maintaining the guide

`docs/SCRIPT_DEVELOPMENT.md` is the authored source. The native bundler invokes
`tools/build_script_docs.lua` to generate `src/runtime/script_development_docs.lua`
before collecting modules. Each second-level heading becomes a stable lowercase
underscore section key. Do not edit the generated module directly.

When changing this guide or its reader, manually review prose, tool argument
examples, source examples and generator changes first. Build with
`luajit tools/bundle.lua --native`, inspect the generated reference and bundle,
then run the focused `luajit test/scripting_docs.lua` integration check.
`luajit tools/bundle.lua --native --check` verifies freshness without writing.
If a section is added/renamed, update the reader's section enum. Keep the prompt
pointer short; extended instructions belong here and are read on demand.

The UI library guide and its bundle have their own build and version. Refer to
`ui_library_docs` for that API rather than maintaining a competing copy of every
control in this guide. Updating scripting guidance alone does not rebuild UI LIB.
]=],
		},
	}
end
