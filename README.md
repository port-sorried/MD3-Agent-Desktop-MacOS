# MD3Agent for macOS

a native swift 6 macos implementation alongside the original kotlin desktop application. the native target uses swiftui, appkit, foundation networking, sqlite, and the security framework. it does not embed a jvm or web renderer.

this migration is **not yet at full functional parity**. macos ci has compiled debug and release, run the test suite, packaged the application with its icon, and created the installer disk image. interactive app-control permissions, microphone behavior, and notarized releases have not been verified. do not treat a successful ci build as an interactive acceptance test.

## native capabilities

- openai-compatible chat completions, anthropic messages, native ollama chat, and custom openai-compatible endpoints.
- incremental sse and newline-delimited json decoding, indexed tool-call assembly, cancellation, output limits, and provider usage reporting.
- actor-isolated conversation context and sqlite storage for conversations, preferences, memories, and tool run logs.
- credentials in macos keychain, scoped to the exact provider endpoint.
- bounded subprocess output, timeout controls, a minimal child environment, and per-invocation tool approval.
- workspace file operations, lexical memory search, and saved-chat search tools.
- native split-view history/chat/inspector layout, lazy chat rows, inline markdown, fenced code copying, text-file attachments, and settings.
- menu bar controls and a control-option-space global shortcut without accessibility permission.
- a macos notch task panel with elapsed time, hover details, active-tool status, allow-once/deny controls, and stop/open-chat actions.
- the original material 3 brand palette, tonal surfaces, rounded conversation cards, capsule controls, light/dark appearance, and reduced-motion-aware scrolling.

the package builds arm64 directly for apple silicon. this removes the java runtime from the native target, but no memory or performance benchmark has been run. intel builds are configurable; the release workflow currently publishes arm64 only.

## install from a disk image

download `MD3Agent-installer-macos-arm64` from a successful native macos build in github actions and extract the artifact zip. open the `.dmg` inside, drag `MD3Agent.app` onto the `Applications` shortcut, eject the image, and launch the app from applications. the artifact also includes a sha256 checksum. `native-coverage` is only a test report, not an installer.

ci development images are ad-hoc signed and are not notarized. macos may block first launch; only for a build you trust, use system settings, privacy & security, open anyway. tagged releases additionally sign and notarize the image when the required apple credentials are configured. a `.dmg` does not by itself bypass gatekeeper or install privileged services.

## prerequisites

- macos 14 or newer.
- xcode 16 or newer with swift 6 and command line tools selected. ci selects xcode 16.4 on `macos-15`.
- an api endpoint and model id, or ollama running locally with a downloaded model.
- python 3 only if enabling the python execution tool or generating the source bundle.

## build and run

from the repository root on macos:

```bash
swift package resolve
swift build -c debug
swift test --enable-code-coverage
swift run MD3Agent
```

open `Package.swift` in xcode, select the `MD3Agent` scheme and `my mac`, then run. this repository uses an spm executable rather than a checked-in xcode project. xcode's package scheme can also be built from the package directory:

```bash
xcodebuild -list
xcodebuild -scheme MD3Agent -destination 'platform=macOS' -configuration Debug build
```

the `xcodebuild` commands require macos verification; scheme availability is determined by the installed xcode. use `swift build` as the canonical package build.

create a locally ad-hoc-signed app bundle:

```bash
bash scripts/package-macos.sh
bash scripts/create-dmg.sh
open dist/MD3Agent.app
```

the packaging script defaults to arm64 release. set `ARCHITECTURE=x86_64` for intel, `VERSION=1.2.3` for a version, and `SIGNING_IDENTITY` to a developer-id identity for hardened-runtime signing. ad-hoc signing is for local use and does not establish gatekeeper trust.

## configure a provider

open settings, then model provider. select the protocol, enter the complete endpoint url and exact model id, and set the context/output token limits to values supported by that model. enter the api key and choose `save key in keychain`. the field clears after saving. deleting a saved key removes its generic-password item.

| protocol | full endpoint example |
| --- | --- |
| openai | `https://api.openai.com/v1/chat/completions` |
| anthropic | `https://api.anthropic.com/v1/messages` |
| ollama | `http://127.0.0.1:11434/api/chat` |
| custom | the provider's complete openai-compatible chat-completions url |

for local ollama, start its server outside the app, download a model using ollama's documented workflow, choose ollama in settings, and enter the installed model's name. leave the api key empty if the local server does not require one. the app does not install or manage ollama.

remote endpoints require https. plaintext http is accepted only for literal loopback hosts. redirects are rejected to prevent credential forwarding. custom headers exist in the configuration model but do not yet have a dedicated settings editor; do not put credentials in custom headers because preferences are not encrypted.

## permissions and security

### application control

enable `управление приложениями` in tools & security to expose native system tools to the agent. it is off by default. the agent can list running apps, open an installed app by bundle id, inspect its accessibility tree, press an inspected element, and replace text in an editable field. `запросить доступ` opens the macos accessibility permission prompt; enable MD3Agent in system settings, privacy & security, accessibility, then use `проверить`.

every system tool requires an allow-once approval, including inspection and app launching, even if its policy is auto. the master switch is checked again at execution time, so it can revoke access during a running task. inspected element ids expire after 60 seconds and are invalidated after an action. password fields are excluded. inaccessible/custom-drawn interfaces may not expose usable controls; the app reports failure instead of pretending to click them. no screen recording or arbitrary applescript is used. granting accessibility access is powerful: ui text and typed content can reach the selected model and local run logs.

### voice activation

in the `голос` settings tab, choose a wake name and recognition language, then enable `откликаться на имя через микрофон`. grant microphone and speech-recognition permission when macos asks. say the name and command in one phrase, for example `агент открой заметки`. after a short pause, the command is submitted to the current conversation if the agent is idle and the draft is empty. recognition must support on-device processing for the selected language; otherwise the feature stays stopped with an error, without falling back to cloud audio processing.

the microphone remains active while the mode is enabled and successfully listening, including when another application is foreground. its status appears in settings and an orange microphone indicator with an off button appears in the chat composer. disabling the toggle stops capture immediately; sleep and quitting also stop it. after sleep or a recognition error, use the reconnect button. recognition sessions rotate periodically to avoid retaining an unlimited transcript. only the command text is sent to the configured model, not ambient audio. wake recognition is not speaker authentication, so other people or speaker playback can trigger it. voice cannot approve tool requests. system interaction and voice activation have separate switches and both default to off.

every tool has an off, ask, or auto policy. all non-shell tools default to ask; shell and python default to off. ask displays the tool name and complete arguments and requires an allow-once decision. a running agent uses a policy snapshot; the system-control master switch can additionally revoke native app-control access immediately.

`run_command` and `run_python` execute as your user. they can access anything your user can access, including files outside the workspace and the network. **the working directory is not a sandbox.** the distribution deliberately disables app sandbox and does not invent a subprocess entitlement. system execution is incompatible with claiming that arbitrary code is isolated by app sandbox.

child processes receive a minimal environment instead of inherited provider secrets. output capture is bounded and the direct child is terminated on cancellation or timeout. descendant process-tree cleanup is not guaranteed. do not use this implementation for hostile code execution.

workspace file tools reject absolute paths, traversal, and resolved symlinks escaping the workspace. these checks are not a race-proof filesystem sandbox against another process mutating paths concurrently. imported attachments currently support utf-8 text only, up to 1 mib per file. attachments are sent to the configured model as part of the prompt.

conversations, memory, tool output, and preferences are stored in `~/Library/Application Support/MD3Agent/agent.sqlite`; imported files and command output files live in its `workspace` directory. the directory is private to your user, but the database is not encrypted. tool run logs can contain sensitive command output. provider credentials are stored separately in keychain.

context pruning removes complete older user turns without splitting assistant tool requests from their results. the token counter uses a conservative utf-8-byte estimate, not a model tokenizer. removed turns remain in the database. model-generated summarization and semantic memory retrieval are not yet ported.

## task panel at the notch

the native macos target shows a black task panel at the top of the display, inspired by the interaction in [ClaudeNotch](https://github.com/CraftStick/ClaudeNotch). this is an independent implementation for this application's own agent, not a claude-code hook integration. it does not copy the reference project's character or sprites.

the compact panel leaves the physical camera housing clear and shows status and elapsed time on either side. hover to see the submitted task, current tool, token counts, and stop/open-chat controls. a pending tool approval expands the panel automatically and offers allow-once and deny using the same approval continuation as the main window. completion, failure, and cancellation have distinct statuses. the timer stops when the run finishes.

the panel prefers a connected display with a physical notch and otherwise uses a virtual notch centered at the top of the main display. display geometry is recalculated when screens change. it uses a nonactivating appkit panel so hovering and approving do not take keyboard focus from the current application. no screen recording, automation, or accessibility permission is requested. turn it off with `показывать задачу у челки` in general settings. task titles and arguments are visible on the display, so disable the panel before sharing the screen if those are sensitive.

26 portable tests pass after this addition, including three geometry tests for physical notches, offset external displays, and small display bounds. swift syntax parsing passes for the new macos files. visual placement, full-screen behavior, first-click controls, and swiftui/appkit typechecking still require macos verification.

## remaining parity

the original kotlin source remains under `app/` and can still be built with its gradle workflow. the audit and full ledger are in [docs/macos-port.md](docs/macos-port.md).

not yet ported: gemini, key rotation, reasoning signatures and controls, model discovery, semantic embeddings, agent profiles, automatic titles/compaction, edit/regenerate/fork, folders, encrypted phone imports, multimodal attachments, image generation, web/weather tools, charts/diagrams/math, interactive questions, reminders/alarms, notifications, voice, mcp transports/oauth, and single-instance deep-link dispatch. the current native markdown renderer supports inline formatting and fenced code, not the full reference renderer.

macos debug/release builds, tests, ad-hoc signing, icon generation, and dmg creation passed in [run 39657140833](https://github.com/port-sorried/MD3-Agent-Desktop-MacOS/actions/runs/39657140833) for commit `02b3817`. live-provider integration, ui behavior, keychain prompts, global hotkeys, accessibility interaction, microphone recognition, developer-id signing, and notarization remain unverified. the native target should be considered an incremental implementation, not a production-ready replacement.

## ci and releases

`build-and-test.yml` resolves the package, builds debug and release, runs swift tests with coverage, exports lcov, and packages an ad-hoc-signed application inside a compressed `.dmg` with an applications shortcut and checksum on macos.

`release.yml` runs for `v*` tags. it requires a protected `release` environment and these secrets:

- `MACOS_CERTIFICATE_BASE64`: base64-encoded developer-id application certificate with private key, exported as p12.
- `MACOS_CERTIFICATE_PASSWORD`: p12 password.
- `MACOS_KEYCHAIN_PASSWORD`: temporary ci keychain password.
- `MACOS_SIGNING_IDENTITY`: full developer-id application signing identity.
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`: notarization credentials.

the workflow fails if any secret is absent. it tests, builds, signs, submits to notarization, staples the ticket, checks gatekeeper assessment, and publishes a zip plus sha256 with generated release notes. it has not been executed from this environment. no commits have been pushed and no release has been published.

## verification and complete source

the portable package target can run on linux with swift 6 and sqlite development headers. it excludes the macos network streaming transport, keychain wrapper, agent engine, and interface; passing it is not a macos build result.

```bash
swift test --jobs 2 --enable-code-coverage
python3 scripts/export-native-source.py
```

[docs/native-source.md](docs/native-source.md) contains complete native source, tests, packaging, workflows, and documentation with relative path headers. regenerate it after editing those files.

## license

GPL-3.0. the existing [LICENSE](LICENSE) is preserved.
