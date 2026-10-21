# native macos architecture and parity ledger

the kotlin application remains the reference implementation. the swift package is a separate native target. a checked-in implementation is not proof of runtime parity or a passing macos build.

## source map

| area | reference source under `app/src/main/kotlin/dev/huecoder/md3agent/` | native destination |
| --- | --- | --- |
| dependency composition | `AppContainer.kt` | main-actor application model |
| agent loop and cancellation | `conversation/ConversationRunner.kt`, `ToolApprovals.kt`, `UserPrompts.kt` | agent engine and explicit approval queue |
| provider transports | `llm/ChatCompletionClient.kt`, `llm/wire/` | `LLMClient.swift`, `StreamParser.swift` |
| tool-call assembly | `llm/ToolCallAccumulator.kt` | indexed stream accumulator |
| prompts and compaction | `prompt/SystemPromptRenderer.kt`, `conversation/Compaction.kt` | `AgentContext.swift` |
| persistent data | `data/db/AppDatabase.kt`, `Entities.kt`, `Daos.kt` | sqlite actor with prepared statements |
| secrets | `data/settings/SecretCipher.kt`, `system/secrets/` | security framework keychain wrapper |
| memory | `data/memory/MemoryStore.kt`, `MemoryRanking.kt` | durable memory records and retrieval |
| command execution | `system/shell/`, `system/python/PythonRuntime.kt` | bounded subprocess runner with explicit approval |
| files and attachments | `data/attachments/`, `data/files/`, `system/files/` | workspace file operations and native import |
| interface | `app/DesktopApp.kt`, `ui/navigation/`, `feature/` | swiftui split view and settings |
| global shortcuts | `system/shortcuts/GlobalShortcuts.kt` | carbon registered hotkey |
| clipboard | `system/clipboard/` | appkit pasteboard |
| notifications and alarms | `system/notifications/`, `system/reminders/` | user notifications |
| external connectors | `mcp/`, `mcp/auth/` | separate parity requirement |
| voice | `voice/`, `llm/TranscriptionClient.kt`, `VoiceListClient.kt` | separate parity requirement |
| phone import/export | `data/transfer/` | separate parity requirement |

## observed behavior

the source uses coroutine state flows for streamed drafts, activity, settings, and windows. `AppContainer` wires repositories, network clients, shell access, tools, and a shared supervisor scope. `ConversationRunner` runs a cancellable job per chat, recovers interrupted streams, supports regenerate/edit/resend, compacts context through a model-generated summary, and recalls memory once per user message.

provider formats include openai-compatible chat completions, anthropic messages, and gemini generate content. provider keys rotate with failover only before visible output. reasoning signatures, usage, model catalogs, embeddings, transcription, and generated images are distinct source features, not interchangeable with text streaming.

room wraps sqlite tables for chats, messages, folders, memories, and reminders. settings and drafts use json. secrets use the linux secret service with a local fallback. memory supports instant and long-term tiers, lexical ranking, and optional embeddings with lexical fallback.

the reference toolbox includes web search, webpage reading, weather, ui/chart/diagram display, user questions, memory crud/search, commands, python, files, reminders/alarms/timers, chat search/export, and dynamically supplied mcp tools. permissions are off, ask, or auto. linux shell isolation uses bubblewrap; system mode has user-level access.

the interface includes home/history, chat, files, agent profiles, playground, settings, model selection, a quick-question overlay, and alarm windows. markdown includes pictures, albums, code, math, charts, and diagrams. desktop behavior includes clipboard attachments, global shortcuts, single-instance dispatch, notifications, systemd timers, and speech.

## native security choices

the developer-id distribution is intentionally not app-sandboxed because a general-purpose system shell cannot be made safe by adding a fictional subprocess entitlement. hardened runtime is enabled during signing. no accessibility entitlement or permission is needed for a carbon registered hotkey. no network-server entitlement is needed for an outbound client in a non-sandboxed app. no keychain access group is required for the app's own generic-password items.

shell tools are disabled by default and must be explicitly enabled. a working directory is not a sandbox. child processes must receive a minimal environment, never the application's provider keys. tool outputs and imported files remain untrusted content. runtime permissions must be checked outside model-generated arguments.

local networking is allowed for ollama; remote provider endpoints require https. microphone and speech permissions are requested only by a user-started voice feature. the app must not request unrelated automation, screen recording, or accessibility access.

## verification contract

the implementation host is linux and has no swift compiler on its path. macos frameworks, signing, keychain prompts, global hotkeys, and accessibility behavior cannot be verified here. macos ci must compile debug and release, run tests, and package the app. notarization requires repository secrets and apple credentials; creating a workflow does not prove a notarized release exists.

the parity ledger must be updated with implemented features and remaining gaps before this migration is reported complete. preserving the kotlin source allows comparison and prevents a partial native implementation from destroying working functionality.

## implementation status

| feature | checked-in native implementation | verification |
| --- | --- | --- |
| spm package and metadata | present, macos 14 and swift 6 | portable manifest compiled |
| provider wire formats | openai-compatible, anthropic, ollama | request/decoder unit tests pass; live streaming untested |
| stream framing | bounded sse and json lines, split utf-8, crlf, bom, trailing events | tests pass |
| tool calls | indexed accumulation, empty inputs, per-call approval, round budget | accumulator and registry tests pass; engine macos-only |
| context | actor, conservative byte estimate, whole-turn pruning, tool schema budget | pruning tests pass; no summary compaction |
| persistence | sqlite prepared statements, transactions, conversations, memories, logs, preferences | sqlite round-trip/deletion tests pass |
| secrets | generic-password keychain wrapper | macos verification required |
| subprocesses | bounded pipes, timeout, cancellation, minimal environment | portable tests pass; descendants not guaranteed terminated |
| workspace tools | list/read/write, canonical path checks | traversal, symlink and approval tests pass; no race-proof isolation |
| memory | durable records, add/list/delete, lexical search | storage tested; no embeddings or automatic recall |
| chat tools | list/read/search | compiled on linux; no legacy database import |
| swiftui interface | split view, lazy rows, drafts, inspector, approvals, settings | syntax parsed only |
| markdown | inline formatting and fenced code copy | no full block, math, image, chart or diagram parity |
| attachments | text picker and file-url drop, private workspace copy | no multimodal, pasteboard file import, or persistent attachment metadata |
| native shell integration | menu bar, carbon hotkey, text clipboard | macos verification required |
| ci/release | macos build/test/coverage, developer-id signing/notarization/zip release | shell syntax and plist parsing pass; workflows not executed |

## outstanding source parity

gemini wire format; key rotation and failover; signed reasoning blocks and model controls; model catalogs and pricing; embeddings and instant-memory injection; prompt-template variables; agent profiles, voices and looks; automatic titles and summary compaction; edit/regenerate/resend/fork; folders and file library; encrypted phone import/export; images and generated images; web search backends, page extraction and weather; charts, diagrams, math and interactive ui/questions; reminders, alarms, timers and notification actions; dictation, transcription and speech; mcp stdio/http, oauth, elicitation and dynamic tools; single-instance launch routing and deep links; translations and usage dashboards.

these are absent features, not placeholders or silently successful mock implementations. the native app is not a full replacement until these are implemented and macos end-to-end verification passes.

## executed checks

on 2026-10-21, the official `swift:6.0.3` container compiled the portable package in swift 6 language mode and ran 23 swift testing tests with coverage enabled, all passing. sqlite headers and the shared library were mounted from the host. the container warned that no sqlite pkg-config file was present; module-map/header linking still succeeded. an additional standalone compiled verifier passed 24 checks before the final edge-case additions.

all native sources and tests passed the swift frontend syntax parser before the final documentation edits. `bash -n scripts/package-macos.sh` and python plist parsing passed. no macos framework typecheck, live provider request, github workflow, signing, notarization, or ui test was executed. those are release blockers, not claimed successes.
