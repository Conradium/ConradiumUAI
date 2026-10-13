# Project UAI 3.0.0 audit

This release concentrates on less repeated agent work, faster repeated script
inspection and more accurate tool outcomes. It keeps the LuaJIT-compatible
factory-module architecture and the established client presentation layer.
The standalone UI library and bridge/companion implementations are unchanged.

The source inventory contains 206 modules: 198 reviewed and eight explicitly
excluded below. All 174 exported tool names are accounted for. Review is recorded
by module and tool
in the ledgers below, including implementations retained after review. Generated
payload literals are not a manual source-logic audit. The final verification
record gives exact coverage, commands and results after the build gate.

| Area | Inventory | Review record |
| --- | ---: | --- |
| Agent | 16 | [Agent ledger](AUDIT_3.0.0_AGENT.md) |
| Providers | 10 | [Agent ledger](AUDIT_3.0.0_AGENT.md) |
| Embedding | 2 | [Agent ledger](AUDIT_3.0.0_AGENT.md) |
| Network | 12 | Six native modules reviewed; six bridge/relay modules excluded below. |
| Runtime | 58 | [Runtime ledger](AUDIT_3.0.0_RUNTIME.md), [scripting ledger](AUDIT_3.0.0_SCRIPTING.md), supplemental rows below. |
| Tools | 43 | [Core tool ledger](AUDIT_3.0.0_TOOLS.md) and the agent/runtime/scripting ledgers. |
| Client UI | 65 | Existing client reviewed across all three workstreams; exact modules listed in their ledgers. |

| Supplemental module | Review |
| --- | --- |
| `runtime/changelog` | New release entry and existing data-driven renderer/marker contract reviewed; historical release data preserved. |
| `runtime/gravity_docs` | Embedded guide and template reviewed: namespaced state, exact shape contract, bounded settings and explicit cleanup; retained. |
| `runtime/script_development_docs` | Generated from the reviewed scripting guide; section order, continuation content and generated diff inspected after build. |

Eight excluded source modules: `net/bridge`, `net/bridge_commands`,
`net/bridge_connection`, `net/relay`, `net/relay_link`, `net/transport`,
`runtime/bridge_install`, and `runtime/ui_library_docs`. External `desktop/`,
`companion/`, `ui-lib/`, their bundles/manifests, and the UI library guide are
outside scope. Native bundle generation still embeds existing protected modules;
their source bytes must remain unchanged. Website generation updates the client
version/catalogue and its publishing mirror using the reviewed native bundle.

## Evidence and limits

The important improvements are directly observable in focused fixtures: warm
project analysis avoids additional compiles, filename discovery performs no
content reads, a debounce burst owns one wakeup, continued web/HTTP pages do not
refetch, and sorted player pages capture each distance once. Exact-byte checks,
compiler identity, ownership, cancellation and bounded retention remain part of
the relevant contract. These are work counters, not claimed wall-clock speedups.

New schemas and shared bounded validation improve the catalogue's common call
boundary. Per-tool ledgers identify domain changes separately from retained
guarded behavior. The protected `ui_library_docs` definition is unchanged.

Manual review precedes every build and test. Build outputs are inspected before
focused verification; fixes are reviewed before rebuilding and retesting. The
entire native suite is excluded at the user's request. See
[TESTING_3.0.0.md](TESTING_3.0.0.md) for actual outcomes and native follow-up.
Synthetic tests do not verify native rendering, real host-input delivery,
provider quality, server acceptance or native throughput.
