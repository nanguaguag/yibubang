# Yibubang guide

Updated 2026-11-13 · [中文](README.md) · [Documentation](../README.md) · [Current progress](../CURRENT_STATUS.md)

Yibubang is an offline-first medical question-bank and revision app for Android, macOS, Windows and Linux; iOS adaptation is in progress. Practice, tests, saved questions, notes, daily revision and statistics use local storage. Question banks are read-only; personal state is stored separately and shared across banks by global question ID.

## AI search and textbooks

AI Search sits between Daily Plan and Statistics by default. It supports streamed answers, follow-up questions, editing/retrying, stopping and local conversation history. Citations open an installed question or the original textbook page. Textbook search includes book filters, keyword highlights, thumbnails, zoom, page navigation and an offline page cache.

Settings→AI Search contains the built-in answer model, rephrasing, streaming, evidence count and textbook/question split. Defaults: rephrasing and streaming enabled, 12 evidence items split 8:4. Evidence count is configurable from 1–25. Each installation has 200 allowance units per Beijing calendar day: basic answers cost 1, rephrasing 2, and rephrasing plus streaming 3. These are app allowance rules, not Google's billing multipliers.

Desktop shortcuts: Shift+Enter sends a question; Left/Right turns textbook pages. Generation requires connectivity; saved conversations and cached pages can be viewed offline. Medical facts, OCR symbols and formulas should be checked against source pages.

The backend uses Google Cloud Run and Discovery Engine's built-in Answer/streamAnswer. There is no separate Vertex model-token generation call. Promotion eligibility and actual bills remain unverified; see [costs](../ai-search/COSTS_AND_BUILTIN_MODELS.md), [retrieval limits](../ai-search/RETRIEVAL_LIMITS.md) and [AI operations](../ai-search/README.md).

## Build and releases

Current source version: 2.2.4+214; user database schema25 and question-bank schema1. Android/macOS Debug builds pass. See [v2.2.4 Release Notes](../release-notes/v2.2.4.md) for details.

Requirements come from [pubspec.yaml](../../pubspec.yaml): Flutter≥3.32.0 and Dart≥3.8.0,<4.0.0. Run from the repository root:

```sh
flutter pub get
flutter run -d macos
flutter build apk --debug
```

Configure your own backend with `--dart-define=AI_SEARCH_ENDPOINT=https://your-service`. Google credentials stay on the server. AI conversations are local and are not included in cross-device sync. Sync protocol-v2 server publication and real-account validation are separate outstanding work.

[GitHub Releases](https://github.com/nanguaguag/yibubang/releases) · [Gitee mirror](https://gitee.com/pumpkin_melon/yibubang/releases) · [Telegram](https://t.me/yibubang) · [MIT License](../../LICENSE)
