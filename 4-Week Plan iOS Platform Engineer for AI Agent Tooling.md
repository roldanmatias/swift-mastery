# 4-Week Plan: Swift Expert and iOS Platform Engineer for AI Agent Tooling

Oct 18, 2026 · @Matías

## Overview

Goal: in 28 days at 8 hours a day, reach expert-level Swift and become interview-ready for a senior iOS Platform role building AI agent tooling at a large company (Airbnb-style posting). The plan covers the full depth of a modern Swift program (Swift 6.4, strict concurrency, SwiftUI with Liquid Glass, architecture, networking, SwiftData, Swift Testing and agentic engineering in Xcode 27), then builds the platform side on top: agent harnesses, large-scale migrations, evals and CI agents. Days 1 to 3 are done and stay as they are. Four weeks won't replace years of experience, but they give you deep, demonstrable skills, a portfolio mapped to the job description and practiced answers for the four interview loops: coding, iOS depth, system design and behavioral.

### Flagship project: SwiftMigrator

An agent pipeline that migrates a real open-source iOS codebase (XCTest to Swift Testing, `ObservableObject` to `@Observable`, or completion handlers to async/await). It combines:

- Deterministic tooling (SwiftSyntax) to find candidates and build a work queue
- An LLM agent that migrates each file, compiles, runs tests and retries using the error output
- Xcode's built-in MCP bridge (xcrun mcpbridge) for `xcodebuild`, tests and previews, plus a small custom MCP server for migration-specific tools
- An eval harness reporting success rate, tokens per file, cost and wall-clock time, before and after optimization

### Daily structure (8h)

- 2h study: docs and courses
- 5h building
- 1h writing notes, metrics and interview talking points

### How you use AI across the sprint

Learning Swift with an agent beside you only works if the agent's role changes as you level up:

| Phase | When | Agent's role | Your role |
| --- | --- | --- | --- |
| Phase 1: the agent as tutor | Days 1 to 7 | Explains concepts, compiler errors and Swift Evolution proposals; quizzes you | You write every line of Swift yourself |
| Phase 2: the agent proposes, you audit | Days 8 to 10 | Proposes views, architecture and tests | You review every diff against your audit checklist and reject what you can't explain |
| Phase 3: the agent builds, you verify | Days 11 to 28 | Implements from specs, runs tests, fixes failures | You write specs, design the gates and verify with tests, evals and diffs |

Rule for every phase: never commit code you can't explain line by line in an interview.

### Spec Driven Development: how you verify agent output

From Day 8 on, every build day runs the same loop. The documents are not the point: the point is that agent output is accepted only when it passes criteria you wrote before the agent started.

1. **Spec.** You write `specs/<feature>/spec.md`: problem, scope, non-goals and numbered acceptance criteria (AC-1, AC-2, …), each one checkable by a test or an eval.
2. **Plan mode.** The agent researches the code in Plan mode, with no edits, and drafts `plan.md`: approach, files touched, risks. You review and approve it before any code is written.
3. **Tasks.** `tasks.md` splits the plan into small tasks; each names the acceptance criteria it satisfies and ends in a check.
4. **Tests.** Every acceptance criterion becomes a Swift Testing test, written before or with its task. A Stop hook (Day 2) runs build and tests, so the agent can't finish on red.
5. **Evals.** For the agent tools themselves (SwiftMigrator, the MCP server, the review agent, the platform agents), acceptance criteria become eval cases with a measured pass rate, cost and latency, not a single green run.
6. **Verify.** You accept the work only when every acceptance criterion maps to a passing test or eval and you've read the diff. Each PR description lists AC → proof, and mismatches go in `retro.md`.

How it ramps up: on Days 8 to 12 you write the spec and audit the plan while the agent proposes the implementation (Phase 2). Day 16 runs the full workflow with spec-kit and subagents. From Day 15 on, every agent tool is built spec-first and gated by evals. Every repo gets a `specs/` folder.

Interview soundbite: "I don't trust agent output, I verify it. Every task starts from a spec with acceptance criteria, the agent plans in Plan mode before touching code, and each criterion becomes a test or an eval. Done means every criterion has passing proof."

### GitHub repos for the sprint

Every study note and exercise lands in one of 10 public repos, so the commit history itself shows 28 days of focus.

| Repo | Purpose | Days |
| --- | --- | --- |
| `<your-username>` (profile README) | Sprint log: one entry per day with links to that day's commits | 1 to 28 |
| `ios-ai-agent-fundamentals` | xcfix agent loop, Claude Code, agentic coding in Xcode and Spec Driven Development | 1, 2, 6, 16 |
| `swiftmigrator` | Flagship: playbook, SwiftSyntax scanner, agent pipeline, evals, optimizations, orchestration | 3, 5, 7, 15, 17 to 22 |
| `swift-mastery` | Swift 6.4 language, concurrency and Swift Testing exercises: one SPM package, every exercise tested | 4, 5, 6 |
| `swiftui-examples-and-testing` | SwiftUI design with Liquid Glass, navigation, SwiftData with ModelActor, testing best practices | 8, 11, 13 |
| `ios-architecture-showcase` | One listings app in 5 architectures on a shared, tested networking Core | 9, 10, 12, 16 |
| `swift-migration-mcp` | Custom MCP server for migration tools Xcode's own MCP bridge doesn't provide | 17 (used on 18 to 21) |
| `ios-pr-review-agent` | GitHub Action that reviews Swift PRs, with an eval set | 23 |
| `ios-platform-lab` | Modular app plus build-break fixer and flaky-test triage agents | 24 |
| `ios-interview-prep` | iOS depth and performance notes, roadmap, Swift DS&A, system design, agent debugging | 14, 22, 25 to 28 |

Commit rules:

- Commit at least 3 times a day with clear messages; never squash the sprint history.
- Tag the end of each day (`day-01` to `day-28`) in the repo you worked in.
- Every repo gets a README on its first day: what it is, how to run it, what you learned.
- Keep STAR stories and anything about clients private; everything else is public.

## Week 1: Agent foundations and Swift mastery

### Day 1: Agent fundamentals

- Read Anthropic's "Building Effective Agents" (anthropic.com/engineering) for the patterns, which still hold (prompt chaining, routing, orchestrator-workers, evaluator-optimizer). Its tooling is from December 2024, so also read [Scaling Managed Agents: Decoupling the brain from the hands](https://www.anthropic.com/engineering/managed-agents) (April 2026), about 30 minutes, concepts only: learn the session (durable event log), harness (the loop) and sandbox (where code runs) split for system design answers. No hands-on Managed Agents work: its cloud sandboxes can't run Xcode. Also read, in the Messages docs: [Tool use overview](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview), [How tool use works](https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works), [Tutorial: Build a tool-using agent](https://platform.claude.com/docs/en/agents-and-tools/tool-use/build-a-tool-using-agent), and [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices).
- Build **xcfix**, an iOS build-and-test fixer agent, as a hand-written agent loop with no framework (Python). Follow the step-by-step below.

* [ ] Milestone: explain the agent loop, tool calls, stop conditions, and workflow vs agent from memory.

**GitHub:** `ios-ai-agent-fundamentals/01-agent-loop`: xcfix source, the seeded-bug branches, eval script, traces, results table and a README with the loop diagram and design decisions, and `notes/building-effective-agents.md`, plus notes/managed-agents.md comparing your hand-written loop with the session / harness / sandbox model. Create the profile README sprint log with the Day 1 entry.

#### Day 1 project: xcfix, the agent loop to show in interviews

**What it does:** you point it at an Xcode project or Swift package with a broken build or failing tests. It builds, reads the compiler errors, finds and edits the code, rebuilds and reruns tests until everything is green or it runs out of budget. It is the core of SwiftMigrator and of the Day 24 build-fixer, so you reuse it all sprint.

**Why it impresses:** instead of a generic `run_command`, it uses narrow, safe, iOS-specific tools; the harness verifies success instead of trusting the model; and every run produces metrics. Those are the three things a senior platform interviewer looks for.

**Stack:** Python 3.12, the official `anthropic` SDK (there is no official Swift SDK), Claude Sonnet as the main model, `xcodebuild`, `ripgrep`, `git`.

**Step by step (about 5 hours):**

1. **Set up the target (30 min).** Create **ListingsKit** at `ios-ai-agent-fundamentals/01-agent-loop/fixtures/ListingsKit`: a Swift package for a stay-listings feature with a `Listing` model, an async `ListingsService`, a price formatter and unit tests. Make 5 git branches, each with one seeded bug: a type mismatch, a missing import, a Swift 6 `Sendable` / `@MainActor` error, a renamed API, and a failing test assertion. Name the branches `bug/type-mismatch`, `bug/missing-import`, `bug/sendable`, `bug/renamed-api` and `bug/failing-test`. These become your eval set.
2. **Define 6 narrow tools with JSON schemas (1 h).**
   - `search_code(pattern, glob)`: ripgrep, capped at 50 matches.
   - `read_file(path, start_line, end_line)`: line ranges, so the model never pulls a whole large file.
   - `edit_file(path, old_str, new_str)`: exact, unique string replacement; reject if not found or ambiguous. Safer and cheaper than `write_file`.
   - `run_build()`: runs `xcodebuild build` (or `swift build`), parses only `error:` lines into `file:line: message`, returns at most 30 lines.
   - `run_tests()`: runs `xcodebuild test`, returns only failing test names and assertion messages.
   - `finish(summary)`: the model signals it is done.
   - Every path is resolved and rejected if it leaves the project root.
3. **Write the loop (1 h).** Send the system prompt, tools and messages; for each `tool_use` block (handle parallel calls), run the tool and return a `tool_result`, with `is_error: true` and a clear message on failure so the model can recover. Stop on `finish`, `end_turn`, a max of 25 turns, or a token budget.
4. **Make the harness verify (30 min).** When the model calls `finish`, the harness runs build and tests itself. If they fail, it sends the failures back and continues. The model never decides success alone.
5. **Add safety and rollback (30 min).** Commit a git checkpoint before the run and after each successful build. Roll back if the run fails. Guardrails: reject edits that delete test assertions or add `@unchecked Sendable` or `// TODO` shortcuts.
6. **Add efficiency (30 min).** Prompt caching on the system prompt and tool definitions; truncate old build logs in history to their last error summary; track tokens per turn.
7. **Add tracing (30 min).** Write one JSONL line per turn: tool, arguments, latency, input/output/cached tokens, cost. Print a run summary at the end.
8. **Run the mini eval and write the README (30 min).** A script runs xcfix on all 5 branches and outputs a table (fixed?, turns, tokens, cost, seconds). The README gets a Mermaid diagram of the loop, the results table and a "Design decisions" section.

- [ ] Milestone: xcfix fixes at least 4 of 5 seeded bugs, with a results table and traces committed.

**Interview talking points:** why narrow tools beat a shell tool (safety, token cost, reliability); why the harness verifies instead of trusting the model; how error messages in `tool_result` drive self-correction; how you would scale it to 2,000 modules (Days 15 and 21); and what your traces revealed about where tokens go.

### Day 2: Claude Code and agentic coding in Xcode

- Anthropic Academy course "Claude Code in Action". Claude Code docs: CLAUDE.md, subagents, hooks, skills, headless mode (`claude -p`), git worktrees.

* Agentic coding in Xcode 27: watch the WWDC26 sessions on Xcode agentic coding ("Xcode, agents, and you") and Apple's "Meet agentic coding in Xcode" tech talk; read Apple's "Giving external agentic coding tools access to Xcode".
* Install Claude Agent from Xcode settings and practice planning, building SwiftUI views verified with Previews, checkpoints and rollback, and plugins with custom skills.
* Connect the Claude Code CLI to Xcode: `claude mcp add --transport stdio xcode -- xcrun mcpbridge`. Requires macOS 26 or later on Apple silicon.

- [ ] Milestone: a script runs headless Claude Code over 5 files of an iOS repo, one worktree per task.

* [ ] Milestone: the same task done three ways (Claude Agent in Xcode, Claude Code CLI with Xcode's MCP bridge, headless script), compared on speed and quality.

**GitHub:** `ios-ai-agent-fundamentals/02-claude-code`: example `CLAUDE.md`, a hook, a skill, a subagent definition, `scripts/headless-migrate.sh` (5 files, one worktree each) and `notes/claude-code.md`, notes/xcode-agentic-coding.md with the three-way comparison, and notes/xcode-mcpbridge-tools.md listing every tool the bridge exposes.

### Day 3: Modern Swift (the migration targets)

- Swift 6 migration guide (swift.org), strict concurrency, actors, Sendable, Swift Testing, Observation framework.
- Manually migrate one module, then write a migration playbook: the rules the agent will follow.

* [ ] Milestone: playbook with before/after examples and edge cases, ready to use as prompt context.

**GitHub:** create `swiftmigrator`. Add `playbook/MIGRATION_PLAYBOOK.md`, `fixtures/` with the module before and after your manual migration, and `notes/swift6-concurrency.md`.

### Day 4: Swift 6.4 language core (Phase 1: the agent as tutor)

- Types and semantics: value vs reference types, copy-on-write, structs, classes, enums with associated values and pattern matching, optionals, extensions.
- Functions and closures: argument labels, `inout`, escaping closures and capture lists, higher-order functions, key paths, functional style (`map`, `compactMap`, `reduce`, lazy sequences).
- Protocols and generics: protocol-oriented design, associated and primary associated types, `some` vs `any`, generic constraints, conditional conformance, parameter packs.
- Errors and data: `throws`, typed throws (`throws(ListingError)`), `Result`, `Codable` basics.
- Advanced language: result builders, property wrappers, macros (`@Observable` is one), noncopyable types (`~Copyable`), `Span` and `InlineArray`.
- New in Swift 6.4: `AType?` shorthand for optional `some`/`any` types, module-qualified names (`Module::Name`), `@diagnose`, noncopyable types conforming to `Equatable` / `Hashable`, `UniqueArray` / `UniqueBox`, Swift Build as the default build system.
- Tutor mode: ask the Xcode 27 agent to explain, quiz you and review your answers. It never writes the solution.

* Ownership exercise (noncopyable types): build a `~Copyable` `ReservationLock` with a `consuming func release()` so the compiler forbids any use after release; a noncopyable enum state machine (`draft` → `confirmed` → `cancelled`) driven by `consuming` transitions; a generic `Box<T: ~Copyable>` with `extension Box: Copyable where T: Copyable`; `borrowing` vs `consuming` parameters. Then replace an `Array` hot path with `InlineArray`, read it through a `Span`, and measure the difference.

**Resources for Day 4**, in study order. The official book is the backbone; the WWDC sessions and Swift Evolution proposals cover what it explains briefly.

| Topic | Best resource |
| --- | --- |
| Everything in the list, from basics to macros | [The Swift Programming Language](https://docs.swift.org/swift-book/) (official book, kept current): Structures and Classes, Enumerations, Closures, Protocols, Generics, Opaque and Boxed Protocol Types, Error Handling (typed throws), Result Builders, Macros |
| Value semantics, protocols and generics in depth | *Advanced Swift* by objc.io, 5th edition (2022). Still the best depth book, but it predates typed throws and noncopyable types, so pair it with the rows below |
| `some` vs `any`, protocol design | WWDC22 [Embrace Swift generics](https://developer.apple.com/videos/play/wwdc2022/110352/) and [Design protocol interfaces in Swift](https://developer.apple.com/videos/play/wwdc2022/110353/) |
| Macros | WWDC23 [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166/) |
| Noncopyable types, `borrowing` / `consuming` | WWDC24 [Consume noncopyable types in Swift](https://developer.apple.com/videos/play/wwdc2024/10170/), then SE-0390 (noncopyable types) and SE-0427 (noncopyable generics) |
| `InlineArray`, `Span`, performance | WWDC25 [Improve memory usage and performance with Swift](https://developer.apple.com/videos/play/wwdc2025/312/), then SE-0447 (`Span`) and SE-0453 (`InlineArray`) |
| Typed throws, parameter packs | SE-0413 (typed throws) and SE-0393 (parameter packs) on [Swift Evolution](https://www.swift.org/swift-evolution/) |
| What's new in Swift 6.4 | [What's New in Swift 6.4?](https://www.kodeco.com/53754585-what-s-new-in-swift-6-4) (Kodeco) and [InfoQ's release summary](https://www.infoq.com/news/2026/09/swift-6-4-released/) |
| Extra practice | The [Exercism Swift track](https://exercism.org/tracks/swift), with mentor feedback, for exercises beyond your 30 |

Tutor-mode tip: read a book chapter or proposal first, then ask the Xcode agent to quiz you on it before you write the exercise.

- [ ] Milestone: 30 exercises solved by hand, each with tests, and you can explain value semantics, `some` vs `any`, typed throws and ownership (`~Copyable`, `borrowing` / `consuming`, `Span`) without notes.

**GitHub:** create `swift-mastery`: one SPM package with `Sources/Language/` (one file per topic), `Sources/Ownership/` for the noncopyable exercises and benchmark, Swift Testing tests for every exercise, and `notes/swift-6.4-language.md`.

### Day 5: Concurrency in depth

Day 3 covered the Swift 6 migration basics; today goes deep enough to explain any concurrency diagnostic in an interview.

- Isolation: isolation domains, `@MainActor` and global actors, actors and reentrancy, `nonisolated`, `isolated` parameters.
- Data-race safety: `Sendable`, region-based isolation and `sending`, why `@unchecked Sendable` is a last resort.
- Approachable concurrency (Swift 6.2 and later): default `MainActor` isolation for app targets, `nonisolated(nonsending)` async functions that run on the caller's actor, and `@concurrent` to move work off it explicitly.
- Structured concurrency: `async let`, task groups, cancellation, `Task` vs `Task.detached`, `AsyncSequence` and `AsyncStream`; Swift 6.4's `await` inside `defer` and `withTaskCancellationShield` for cleanup.
- Tutor mode: paste real diagnostics into the Xcode agent and have it explain them; you write the fix.

* [ ] Milestone: a second, harder module (actors, async streams, a reentrancy bug) migrated by hand with zero warnings, and the playbook upgraded to v2 with approachable-concurrency and `@concurrent` rules.

**GitHub:** `swift-mastery/Sources/Concurrency/` with exercises and tests; `swiftmigrator/playbook/MIGRATION_PLAYBOOK.md` v2 and the new module in `fixtures/`.

### Day 6: Swift Testing in depth (tests as the agent's oracle)

- Swift Testing: `@Test`, `@Suite`, `#expect`, `#require`, parameterized tests, traits (`.tags`, `.timeLimit`, `.enabled(if:)`, `.bug`), `confirmation` for events, exit tests, attachments, and coexisting with XCTest.
- Testing async code and actors deterministically: injected clocks and controlled streams, never `sleep`.
- Test doubles: protocol-based stubs, spies and fakes; when to mock and when not to.
- Why it matters for agents: tests are the only reliable signal an agent has. Write tests that fail for the right reason with a clear message, because xcfix and SwiftMigrator read those messages.

* [ ] Milestone: ListingsKit at 90%+ coverage in Swift Testing, with parameterized and async tests, after migrating its XCTest tests by hand.

**GitHub:** `swift-mastery/Tests/` patterns and `notes/swift-testing.md`; the ListingsKit migration in `ios-ai-agent-fundamentals` (it later becomes a SwiftMigrator eval fixture).

### Day 7: Deterministic tooling

- SwiftSyntax, `xcodebuild` and `xcrun simctl`, SwiftLint, SPM. Skim Bazel and Tuist basics; Airbnb has written about moving its iOS build to Bazel.

* [ ] Milestone: a SwiftSyntax tool that outputs a JSON queue of files to migrate, each with a complexity score.

**GitHub:** `swiftmigrator/scanner`: SwiftSyntax CLI as an SPM executable, Swift Testing tests, and a sample `queue.json`.

## Week 2: SwiftUI and app architecture (Phase 2: the agent proposes, you audit; Phase 3 from Day 11)

This week makes you the person who reviews iOS code at a high bar. The agent drafts; you audit every diff against `AUDIT_CHECKLIST.md` (deprecated APIs, isolation, accessibility, view identity, testability) and grow the checklist each day.

### Day 8: SwiftUI design: layout, navigation and Liquid Glass

- Layout: stacks, `Grid`, `ViewThatFits`, safe areas, `containerRelativeFrame` vs `GeometryReader`, custom `Layout`.
- Navigation: `NavigationStack` with typed paths, `NavigationSplitView` for iPad, sheets and inspectors, deep links, state restoration.
- Liquid Glass (iOS 26 and later): system bars and tab bars, `glassEffect`, `GlassEffectContainer`, glass button styles, and when not to use glass, per Apple's Human Interface Guidelines.
- iOS 17 to iOS 27 without a single deprecated API: `@Observable` instead of `ObservableObject`, `NavigationStack` instead of `NavigationView`, `foregroundStyle` instead of `foregroundColor`, two-parameter `onChange`; gate newer APIs with `if #available` and treat deprecation warnings as errors in CI.
- Accessibility: Dynamic Type, VoiceOver labels, Reduce Motion and Reduce Transparency (critical with glass).

* **Spec first:** `specs/listings-screens/spec.md` with acceptance criteria such as "deep link opens the detail screen", "falls back cleanly on iOS 17" and "zero deprecation warnings". The agent proposes a plan in Plan mode, you audit it, and each criterion becomes a test or a CI check.

- [ ] Milestone: 5 listings screens (list, detail, search, filters, settings) with Liquid Glass on iOS 26+, graceful fallbacks on an iOS 17 deployment target, working deep links and zero deprecation warnings.

**GitHub:** create `swiftui-examples-and-testing` with `Design/`, `Navigation/`, `notes/liquid-glass.md` and `AUDIT_CHECKLIST.md`.

### Day 9: State, dependency injection and MVVM with Clean Architecture

- State ownership: `@State`, `@Binding`, `@Observable`, `@Bindable`, `@Environment`; one source of truth, view identity and lifetime, why an `@Observable` model lives in `@State`.
- Dependency injection: initializer injection, custom environment values with `@Entry`, protocol boundaries, swift-dependencies or Factory, a single composition root.
- MVVM with Clean Architecture: Domain (entities, use cases, repository protocols), Data (repositories, DTOs, mappers), Presentation (`@MainActor @Observable` view models); the dependency rule.
- Supporting patterns: Coordinator / Router for navigation, typed errors mapped to loading / error / empty states.
- Audit drill: ask the agent to propose the module structure, then challenge every dependency arrow before accepting it.

* **Spec first:** `specs/mvvm-clean/spec.md` with criteria like "Domain imports no UI or networking module" and "every use case has unit tests"; enforce the dependency rule with a test or lint rule, not a promise.

- [ ] Milestone: the listings app in MVVM + Clean Architecture with unit tests for use cases and view models, plus an architecture decision record.

**GitHub:** create `ios-architecture-showcase` with the MVVM-Clean variant and `docs/adr/0001-mvvm-clean.md`.

### Day 10: Networking and applied testing

- `URLSession` with async/await: data, upload and download tasks, streaming with `bytes(for:)`, cancellation, timeouts, HTTP status handling.
- Codable in depth: `CodingKeys`, nested containers, custom `init(from:)`, date and key strategies, polymorphic and lossy decoding, versioned payloads.
- Service architecture: a generic API client, typed endpoints, request building, interceptors for auth and retries with backoff, error mapping, caching for offline use.
- Test doubles: `URLProtocol` stubs, protocol fakes, JSON fixtures, contract tests against recorded real payloads.

* **Spec first:** `specs/core-networking/spec.md`: one acceptance criterion per behavior (retry with backoff, error mapping, lossy decoding), each proved by a test against recorded fixtures.

- [ ] Milestone: a shared `Core` networking package with decoding and retry logic fully tested, used by the showcase app.

**GitHub:** `ios-architecture-showcase/Core` (client, endpoints, DTOs, fixtures, tests) and `notes/networking.md`.

### Day 11: Advanced SwiftUI and SwiftData (Phase 3 begins: the agent builds, you verify)

- Two apps, two architectures: the listings app with `@Observable` models and repositories, and a Saved Trips app built on SwiftData.
- SwiftData: `@Model`, relationships, `@Query` with predicates and sorting, `ModelContainer` and `ModelContext`, schema versioning and migrations (`VersionedSchema`, `SchemaMigrationPlan`).
- Background work with `ModelActor`: imports and sync off the main actor, passing `PersistentIdentifier` across actors instead of model objects.
- Advanced SwiftUI: custom containers, animations and transitions, `matchedGeometryEffect`, `scrollPosition`, previews with in-memory model containers.

* **Spec first:** `specs/saved-trips/spec.md` with measurable criteria ("imports 10,000 records with no main-thread hitch over 100 ms", "v1 to v2 migration keeps all data"), proved by tests and an Instruments measurement. From today the agent builds from the approved plan and you verify (Phase 3).

- [ ] Milestone: the Saved Trips app imports 10,000 records through a `ModelActor` without UI hitches, with a schema migration and tests on in-memory containers, plus a README comparing the two architectures.

**GitHub:** `swiftui-examples-and-testing/SwiftData/` (app, `ModelActor` importer, migrations, tests) and `notes/swiftdata.md`.

### Day 12: Architecture showcase: 5 variants

- On the shared `Core`, add MV (SwiftUI-native), TCA, VIPER and a SwiftData-backed variant next to the Day 9 MVVM-Clean version. See Repo 1 in the track below.

* **One spec, five implementations:** a single `specs/listings-feature/spec.md` whose acceptance tests run unchanged against every variant. That shared suite is what makes the architecture comparison fair.

- [ ] Milestone: Repo 1 milestones in the track below.

**GitHub:** `ios-architecture-showcase`: 5 variants, the comparison table and CI.

### Day 13: SwiftUI testing repo

- Snapshot tests, XCUITest with page objects, accessibility audits with `performAccessibilityAudit`, coverage and CI. See Repo 2 in the track below.

* [ ] Milestone: Repo 2 milestones in the track below.

**GitHub:** finish `swiftui-examples-and-testing`, including `TESTING.md`.

### Day 14: Performance and iOS depth

- ARC and retain cycles, the memory graph debugger, GCD vs Swift concurrency, SwiftUI and UIKit interop.
- SwiftUI performance: view identity and dependency tracking, `Self._printChanges()`, the SwiftUI instrument, hangs and hitches, app launch time, build times.
- Airbnb Engineering blog iOS posts: Bazel, modularization, Epoxy, Lottie.

* Lifetime debugging with `@Observable` (exercise): build a view model that starts a long-lived `Task` looping over an `AsyncStream` and capturing `self`. Prove the leak with the memory graph debugger and the Leaks and Allocations instruments, and watch the task stay alive in the Swift Concurrency instrument. Fix it three ways and compare: tie the work to the view with `.task` (cancelled automatically), store the `Task` and cancel it on dismissal, or capture `[weak self]` inside the loop. Avoid `unowned` in task closures: the task can outlive the model and crash.

- [ ] Milestone: profile the Saved Trips app in Instruments and fix one real hitch with before/after numbers, plus the `@Observable` leak reproduced, fixed and verified clean in Leaks; whiteboard a modular iOS architecture and explain its build-system implications.

**GitHub:** create `ios-interview-prep` with `ios-depth/`: Q&A notes, the Instruments write-up and `lifetime-leaks.md`.

## Week 3: Agentic engineering and the agent platform (Phase 3: the agent builds, you verify)

### Day 15: The migration pipeline

- Read Airbnb's engineering post on accelerating large-scale test migration with LLMs: per-file state machine, validation steps, retry loops, rich context.
- Build the pipeline on top of xcfix, the Day 7 scanner and your v2 playbook: migrate, compile, test, lint, retry with error feedback up to N attempts.

* **Spec first:** `specs/pipeline/spec.md` defines each stage's pass condition and the retry policy; the agent plans in Plan mode and the acceptance criteria become eval cases on Day 18.

- [ ] Milestone: the pipeline runs on 50+ files and logs pass/fail per stage.

**GitHub:** `swiftmigrator/pipeline`: state machine, retry logic and logging; `docs/architecture.md`; the run log of the first 50 files.

### Day 16: Agentic engineering in Xcode 27 and Spec Driven Development

- Workflow tools: plan mode first, subagents for parallel research and review, skills for repeatable procedures, hooks as hard gates (from Day 2).
- Protocols: MCP connects agents to tools (Xcode's `xcrun mcpbridge`); ACP (Agent Client Protocol) connects an editor to any compatible agent harness, which Xcode 27 supports under Settings → Intelligence → Agents → Add an Agent. One line to remember: MCP is agent ↔ tools, ACP is editor ↔ agent.
- Spec Driven Development: write `spec.md` (what and why, acceptance criteria), then `plan.md` (architecture and constraints), drafted by the agent in Plan mode and approved by you before any code, then `tasks.md` (small, verifiable tasks). The agent implements one task at a time and every task ends in a passing test. Try GitHub's spec-kit.
- Work like a product team: you are PM and tech lead, one agent session implements, a subagent reviews, another writes tests. Ship one new feature (for example, price alerts) in the showcase app entirely through this flow.

* [ ] Milestone: a feature shipped via spec → plan → tasks with every acceptance criterion covered by a test, plus a retro on where the agent needed correction.

**GitHub:** `ios-ai-agent-fundamentals/03-agentic-engineering`: `specs/price-alerts/` (spec, plan, tasks), `CLAUDE.md`, skills, subagent definitions, `notes/acp-vs-mcp.md`, `notes/sdd-retro.md`; the feature PR in `ios-architecture-showcase`.

### Day 17: MCP (Xcode's bridge + your own server)

- Anthropic Academy "Introduction to Model Context Protocol" and modelcontextprotocol.io.
- Map the tools Xcode exposes through `xcrun mcpbridge` (build, tests, previews, documentation search, symbols, simulators) and use them from SwiftMigrator instead of rebuilding them.
- Build a small custom MCP server only for what Xcode lacks: `next_migration_task`, `apply_playbook_rule`, `run_swiftlint`, `record_eval_result`.
- Interview trade-off: the bridge talks to a running Xcode, so keep an `xcodebuild` fallback for headless CI.

* Make the build tools safe for parallel callers: every call takes a worker ID and runs `xcodebuild` with its own `-derivedDataPath` and `-clonedSourcePackagesDirPath` in an ephemeral directory (or `swift build --scratch-path`), so two agents never fight over the same index or package lock.

- **Spec first:** `specs/swift-migration-mcp/spec.md` defines each tool's contract (inputs, outputs, error cases), and every contract clause becomes a contract test.

* [ ] Milestone: Claude Code fixes a failing test using Xcode's bridge plus your server, with no raw shell commands.

**GitHub:** create `swift-migration-mcp`: the 4 custom tools, tests, a README showing how to register it alongside `xcrun mcpbridge` in Claude Code, and a demo transcript or GIF. Link it from the `swiftmigrator` README.

### Day 18: Evals and observability

- Build a fixed eval set of about 30 files, easy to hard, with expected outcomes. Use your hand migrations from Days 3, 5 and 6 as ground truth.
- Log every run: tokens in/out, cost, latency, retries, failure category.

* Treat the eval set as your acceptance criteria at scale: each case traces back to a criterion in a spec, so a failing case tells you which requirement the agent broke.

- [ ] Milestone: a baseline metrics table, e.g. 62% first-pass success, 1.8 retries per file, $0.14 per file, 95 s per file.

**GitHub:** `swiftmigrator/evals`: the 30-file dataset, the eval harness, and `results/baseline.md` with the metrics table.

### Day 19: Efficiency (tokens, time, cost)

- Prompt caching, context trimming (send only relevant symbols, not whole files), model routing (small model for triage, strong model for hard files), parallel workers, Batch API.

* [ ] Milestone: measurable gains, e.g. cost down 45%, wall time down 60%.

**GitHub:** `swiftmigrator`: one pull request per optimization (caching, trimming, routing, parallelism), each with before/after numbers; `results/optimized.md`.

### Day 20: Reliability and quality

- Failure classification, idempotent reruns, sandboxing, guardrails (no test deletion, no `@unchecked Sendable`, no `// TODO` cop-outs), automatic PR generation with a summary, human-review gates.

* [ ] Milestone: higher success rate plus a written analysis of the remaining failure modes.

**GitHub:** `swiftmigrator`: guardrails, the PR generator and `docs/failure-analysis.md`.

### Day 21: Scale out

- Orchestrate a migration across many modules: a job queue, parallel workers in git worktrees, per-run cost budgets, resumable runs.
- Run it with the Claude Agent SDK on your Mac and on GitHub Actions macOS runners; compare latency, cost and setup.
- Add a GitHub Actions workflow that runs a nightly migration batch and opens PRs.

* Isolation per worker: each worktree gets its own `-derivedDataPath`, cloned-packages directory and simulator (`xcrun simctl clone`), created on start and deleted on exit. Cap parallel workers at what the machine can compile (start around half the CPU cores), not at what the queue allows.
* CI cost and caching: macOS runner minutes cost several times Linux minutes, so cache SPM packages keyed on `Package.resolved`, restore a warm DerivedData cache keyed on Xcode version plus lockfile (expect partial hits, because DerivedData is path- and timestamp-sensitive), pipe output through `xcbeautify` to shrink logs for both humans and the agent's context, and build only the modules a change affects. Set a job timeout and a per-run token budget.

- **Spec first:** `specs/orchestrator/spec.md` with criteria such as "zero DerivedData lock failures", "a killed run resumes without redoing finished files" and "stops at the cost budget"; each one is checked in the run report.

* [ ] Milestone: 100+ files migrated in one orchestrated run, with a cost and time report, zero DerivedData lock failures, and CI time before vs after caching.

**GitHub:** `swiftmigrator/orchestrator`, `.github/workflows/migrate.yml`, and `docs/scaling.md` comparing your Mac vs CI runners, plus one paragraph on why cloud Linux sandboxes (such as Managed Agents) don't fit iOS builds and what a self-hosted Mac fleet would look like.

## Week 4: Platform at scale and interviews

### Day 22: Ship SwiftMigrator v1.0 and measure impact

- Final README with an architecture diagram, the metrics table and trade-offs. Blog post on what moved the needle, also published on Medium or dev.to.
- Developer productivity frameworks (DORA, SPACE, DX Core 4) and how to measure AI tooling: adoption, PR cycle time, migration throughput, review acceptance rate, cost per merged PR.
- Write a 6-month roadmap for AI tooling on an iOS Platform team: priorities, success metrics, risks, adoption plan (including Swift 6 strict concurrency adoption across the codebase).

* [ ] Milestone: release `v1.0` tagged, article published, and a one-page roadmap you can present in 5 minutes, backed by your own metrics.

**GitHub:** `swiftmigrator`: final README, `docs/blog-post.md`, `results/impact-report.md`, release `v1.0`; `ios-interview-prep/roadmap/ai-tooling-roadmap.md`.

### Day 23: AI code review agent

- Build a GitHub Action that reviews Swift PRs with the Claude Agent SDK: isolation and `Sendable` mistakes, deprecated SwiftUI APIs, architecture rule violations, missing tests. Turn your Week 2 `AUDIT_CHECKLIST.md` into the agent's rules (a skill or `CLAUDE.md`).
- Build an eval set of 20 PRs with seeded bugs and measure precision (useful comments) and recall (bugs caught), plus cost per PR.

* **Spec first:** `specs/pr-review-agent/spec.md` sets the release gate as eval thresholds (for example recall ≥ 70%, precision ≥ 80%, cost per PR under budget); the agent ships only when the eval run passes them.

- [ ] Milestone: the review agent catches at least 70% of seeded bugs with few false positives, measured and documented.

**GitHub:** create `ios-pr-review-agent`: the action, rules, eval set, `results/eval.md`, and a demo PR in the repo showing it in action.

### Day 24: iOS build systems and platform engineering

- Modularization at scale: SPM, Tuist and Bazel (rules\_swift), build caching, interface vs implementation modules, and why large apps like Airbnb's moved to Bazel.
- Build a modular sample app, then two platform agents: a build-break fixer (reuses xcfix: reads compiler errors, fixes, verifies with a build) and a flaky-test triager (reruns, classifies, files an issue).

* CI for the platform agents: compute the affected module graph from the diff and build and test only those modules incrementally. Compare cold vs cached runs, and note what Bazel's remote cache gives that DerivedData caching can't: hermetic builds shared across machines.

- **Spec first:** one spec per agent (`specs/build-fixer/`, `specs/flaky-triage/`) with eval thresholds; the seeded broken builds and flaky tests are the eval set.

* [ ] Milestone: both agents work on deliberately broken builds and flaky tests, with success rates recorded, plus cold vs incremental CI times.

**GitHub:** create `ios-platform-lab`: the modular app, `agents/build-fixer`, `agents/flaky-triage`, `docs/build-systems.md` comparing SPM, Tuist and Bazel.

### Day 25: Coding interviews in Swift

- 15 timed NeetCode 150 problems in Swift: arrays, hashing, graphs, trees, intervals.
- One practical exercise: a small SwiftUI feature with networking, async/await and tests in 60 minutes, without agent help.
- Rapid-fire Swift questions: value vs reference semantics, `some` vs `any`, typed throws, actor reentrancy, `Sendable`, `@concurrent`, `@Observable` vs `ObservableObject`, SwiftData `ModelActor`.

* [ ] Milestone: medium problems solved in 30 minutes or less while thinking aloud, and the practical exercise done in 60.

**GitHub:** `ios-interview-prep/dsa-swift` (SPM package, one file per problem, Swift Testing tests) and `practical/`.

### Day 26: System design

1. Design a platform that migrates 2,000 iOS modules with AI agents.
2. Design an AI code-review assistant for a 300-engineer iOS org.
3. Design CI agents that fix build breaks and triage flaky tests.
4. Roll out Swift 6 strict concurrency across a large app using agents and gates.
5. How do you measure whether AI tooling improves developer productivity?

Cover orchestration, queueing, sandboxing (the session / harness / sandbox split from the Day 1 Managed Agents reading), MCP and ACP integration points, evals, cost controls, rollout, and trust and adoption.

- [ ] Milestone: three recorded 45-minute mock answers, self-reviewed.

**GitHub:** `ios-interview-prep/system-design`: one doc per prompt with Mermaid diagrams, trade-offs and self-review notes.

### Day 27: Agent debugging and behavioral

- Practice a likely live exercise: given a slow, expensive or failing agent trace, find the inefficiency and fix it. Use your own traces from SwiftMigrator and the review agent.
- STAR stories mapped to each job-description bullet: migrations, agent optimization, driving a roadmap, code quality. Your EmmRise agent-crew delivery work is a strong source.

* [ ] Milestone: 3 trace-debugging exercises solved and 6 STAR stories rehearsed out loud.

**GitHub:** `ios-interview-prep/agent-debugging`: the traces, your diagnosis and the fix for each. Keep STAR stories private.

### Day 28: Full mock loop and launch

- One full mock interview loop: coding, iOS depth, system design, behavioral, ideally with another engineer.
- Fix the weakest area, polish all READMEs, and start applying.

* [ ] Final milestone: tell the SwiftMigrator story in 2 minutes with numbers, and pass your own mock loop.

**GitHub:** finish the profile README with a sprint summary: key metrics and links to all 10 repos.

## Track: Architecture and SwiftUI repos

Two public repos prove senior-level architecture, design and testing judgment. You build them across Days 8 to 13: the architecture repo on Days 9, 10 and 12, the SwiftUI and testing repo on Days 8, 11 and 13.

### Architectures to learn (and include in the repo)

| Pattern | What to know | Status in 2026 |
| --- | --- | --- |
| MVC | Apple's original UIKit pattern; the "massive view controller" problem | Baseline, legacy code |
| MVVM + Observation | View model as a `@MainActor @Observable` class, async/await loading | Most common default |
| MVVM + Clean Architecture | Domain / Data / Presentation layers, use cases, repository protocols, dependency rule | Large apps, enterprise |
| MV (SwiftUI-native) | Views bind directly to `@Observable` models and services via `@Environment`; no view model per view | Apple's sample-code style |
| SwiftData-backed MV | `@Model` and `@Query` in views, `ModelActor` for background work | Apple's default for local persistence |
| TCA (The Composable Architecture) | Point-Free's unidirectional state, reducers, effects, `TestStore`, dependencies | Popular in SwiftUI teams |
| Unidirectional data flow (Redux-style) | Single store, actions, reducers; the idea behind TCA | Concept to explain |
| VIPER | View, Interactor, Presenter, Entity, Router | Legacy, still in older codebases |
| Coordinator / Router | Navigation pulled out of views; `NavigationStack` with typed paths | Standard for navigation |
| RIBs | Uber's router-interactor-builder trees for very large apps | Know the concept |
| Modular architecture | Feature modules as SPM packages, interface vs implementation modules, Tuist or Bazel | Essential at platform scale |

Cross-cutting practices in every variant: dependency injection with a single composition root, Swift 6 language mode with zero concurrency warnings, the repository pattern over the shared `Core`, typed errors mapped to UI states, feature flags, and no deprecated APIs on an iOS 17 deployment target.

### Repo 1: ios-architecture-showcase (Days 9, 10, 12)

- One listings browser built 5 ways: MVVM + Clean Architecture, MV, SwiftData-backed MV, TCA and VIPER.
- Shared SPM `Core` package: domain models, the networking client from Day 10, persistence. Each variant is a separate feature module.
- README comparison table: boilerplate, testability, team scalability, concurrency story, when to choose each.

* [ ] Milestone: public repo with 5 architecture variants, each with unit tests and a passing GitHub Actions CI.
* [ ] Milestone: a module dependency diagram in the README and a 2-minute spoken explanation of the trade-offs.

### Repo 2: swiftui-examples-and-testing (Days 8, 11, 13)

SwiftUI examples to include:

- Design: Liquid Glass (`glassEffect`, `GlassEffectContainer`, glass button styles) with fallbacks below iOS 26
- Layout: `Grid`, `ViewThatFits`, `containerRelativeFrame`, a custom `Layout`
- State: `@State`, `@Binding`, `@Observable`, `@Bindable`, `@Environment` with `@Entry`
- Navigation: `NavigationStack` and `NavigationSplitView` with typed, deep-linkable paths
- Async loading with `.task`, cancellation, and loading / error / empty states
- SwiftData with `@Query`, migrations and a `ModelActor` importer
- Lists and lazy stacks with performance notes; animations and transitions
- Accessibility (Dynamic Type, VoiceOver, Reduce Transparency) and Previews with mock data

Testing best practices to include:

- Swift Testing: `@Test`, `#expect`, `#require`, parameterized tests, traits and tags
- Unit tests for view models and reducers with protocol-based test doubles
- Testing async code, actors and `ModelActor` deterministically, SwiftData on in-memory containers
- Snapshot tests with Point-Free's swift-snapshot-testing, light and dark, several Dynamic Type sizes
- UI tests with XCUITest using the page-object pattern, plus `performAccessibilityAudit`
- Code coverage report and CI on GitHub Actions with `xcodebuild test`

* [ ] Milestone: public repo with 10+ SwiftUI examples, each covered by tests, CI green, coverage over 80%.
* [ ] Milestone: a `TESTING.md` explaining your testing pyramid and when to use each test type, and the final `AUDIT_CHECKLIST.md` from Week 2.

Resources: [Point-Free TCA](https://github.com/pointfreeco/swift-composable-architecture), [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing), Apple's SwiftUI, SwiftData and Swift Testing documentation on [developer.apple.com](https://developer.apple.com/documentation), WWDC sessions on Liquid Glass, Observation, SwiftData and Swift Testing.

## Core resources

Swift 6.4 (released September 2026) and Xcode 27 are current as of November 2026.

| Area | Resources |
| --- | --- |
| Swift language | The Swift Programming Language on [docs.swift.org](https://docs.swift.org/swift-book/), Swift Evolution proposals, [What's new in Swift 6.4](https://www.infoq.com/news/2026/09/swift-6-4-released/), Swift 6 migration guide on [swift.org](https://www.swift.org) |
| Concurrency and testing | Apple's Swift Concurrency docs, Swift Testing docs, WWDC sessions on concurrency and Swift Testing |
| SwiftUI and design | Apple's SwiftUI docs and tutorials, Human Interface Guidelines (Liquid Glass), WWDC sessions on Liquid Glass and SwiftUI |
| Data and networking | SwiftData docs (`ModelActor`, schema migrations), `URLSession` and `Codable` docs on [developer.apple.com](https://developer.apple.com/documentation) |
| Agentic Xcode | Apple's agentic coding docs and WWDC26 sessions, [using ACP harnesses with Xcode 27](https://redalemeden.com/derived-data/2026/how-to-use-any-harness-with-xcode-27/), [modelcontextprotocol.io](https://modelcontextprotocol.io), GitHub's [spec-kit](https://github.com/github/spec-kit) for Spec Driven Development |
| Agents (Anthropic) | "Building Effective Agents", "Effective context engineering for AI agents" and "Scaling Managed Agents" on [anthropic.com/engineering](https://www.anthropic.com/engineering); [platform.claude.com/docs](https://platform.claude.com/docs): tool use, prompting, prompt caching, Batch API, Claude Agent SDK, Claude Code |
| Courses | Anthropic Academy: Claude Code in Action (done), Building with the Claude API, Introduction to MCP |
| Airbnb | Airbnb Engineering blog (Medium): LLM test-migration post, iOS build and architecture posts |
| Interviews | NeetCode 150; System Design Interview (Alex Xu), adapted to agent platforms |

Confirm current course titles before enrolling.
