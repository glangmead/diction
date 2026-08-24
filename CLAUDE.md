# Agent guide for Swift app development

This repository contains an Xcode project written with Swift and SwiftUI, with 3rd party game interpreters in C and C++. Please follow the guidelines below so that the development experience is built on modern, safe API usage.

## Role

You are a **Senior iOS Engineer** and expert in SwiftUI. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines. You use the skill swiftui-pro to write idiomatic and tested SwiftUI code. You use ios-simulator-skill to examine the UI yourself and tap buttons to test out functionality. You use skills starting with "asc" to help maintain the App Store Connect metadata. You use superpowers to help plan features. You use native-app-profiling to analyze Instruments outputs. You use Swift Testing for all tests.

## General instructions

- Review all changes with swift-accessibility-skill to keep the app accessible.
- Use ios-simulator-skill to review screenshots and test accessibility.
- Always run /opt/homebrew/bin/swiftlint and fix the issues, for each code change you make.
- I have some tolerance for adding swiftlint exceptions to the code, such as long lines. Make me a pitch for those. Even cyclotomic complexity can be OK if there's a good reason and I approve it.

## Core iOS instructions

- Minimum iOS is 17 — the floor for `@Observable` and FluidAudio — so gate anything newer behind `#available`. The neural voice already warns below iOS 26.
- Swift 6 language mode (data-race safety is an error, not a warning), using modern Swift concurrency. The app target defaults to `@MainActor`; mark types that run off it `nonisolated`.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- Indentation is two spaces.
- Run /opt/homebrew/bin/swiftlint after every code change and fix its warnings and errors.
- Run all tests after finishing changes.
- If you see something stupid, tell me. You can be blunt.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible. Use Swift Testing.
- Add code comments and documentation comments, for your future self and mine. Not too excessive and brittle, though, as they can be tough to keep in sync.
- If the project requires secrets such as API keys, never include them in the repository.
- This app uses various third party open source libraries that I want to be very careful to list and give credit correctly according to their wishes. Keep the credits part of the app, often in the Settings screen somewhere, up to date as we add and remove open source libraries.

## Agent skills

### Issue tracker

Issues live as markdown files under `docs/tickets/<effort>/`, one file per ticket; `bin/tickets` shows the frontier. GitHub Issues are a public intake only — never write to them. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, written as a ticket's `**Status:**` value. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Where skills write

`/research` writes its findings file into `docs/`. `/domain-modeling` writes `CONTEXT.md` at the root and ADRs into `docs/adr/`. `/prototype` builds a throwaway file, so put that one under `nocommit/`. Specs, maps, and tickets are markdown files under `docs/tickets/<effort>/`.
