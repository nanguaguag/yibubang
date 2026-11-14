<p align="center">
  <img width="128" src="assets/icon/icon.png" alt="Yibubang Logo"><br>
  <h1 align="center">Yibubang (医不帮)</h1>
  <p align="center"><strong>A Modern, Offline-First, Cross-Platform Medical Exam Preparation App for Medical Students</strong></p>
  <div align="center">
    <a href="https://github.com/nanguaguag/yibubang"><img src="https://img.shields.io/badge/platform-Flutter%203.32%2B-blue.svg" alt="Flutter"></a>
    <a href="https://github.com/nanguaguag/yibubang/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"></a>
    <a href="https://github.com/nanguaguag/yibubang/actions/workflows/android.yml"><img src="https://github.com/nanguaguag/yibubang/actions/workflows/android.yml/badge.svg" alt="Android Build"></a>
    <a href="https://github.com/nanguaguag/yibubang/actions/workflows/macos.yml"><img src="https://github.com/nanguaguag/yibubang/actions/workflows/macos.yml/badge.svg" alt="macOS Build"></a>
    <a href="https://github.com/nanguaguag/yibubang/actions/workflows/windows.yml"><img src="https://github.com/nanguaguag/yibubang/actions/workflows/windows.yml/badge.svg" alt="Windows Build"></a>
    <a href="https://github.com/nanguaguag/yibubang/actions/workflows/linux.yml"><img src="https://github.com/nanguaguag/yibubang/actions/workflows/linux.yml/badge.svg" alt="Linux Build"></a>
    <a href="https://t.me/yibubang"><img src="https://img.shields.io/badge/Telegram-Join%20Chat-26A5E4?logo=telegram" alt="Telegram"></a>
  </div>
  <br>
  <div align="center">
    <strong><a href="README.md">🇨🇳 简体中文 (Chinese Version)</a></strong> •
    <strong><a href="#-table-of-contents">🇺🇸 English (Current)</a></strong>
  </div>
</p>

---

## 📑 Table of Contents

- [💡 Introduction](#-introduction)
- [✨ Key Features](#-key-features)
- [AI Search and Textbook Reading](#ai-search-and-textbook-reading)
- [🗄 Architecture & Database Design](#-architecture--database-design)
- [📚 Supported Question Banks](#-supported-question-banks)
- [📥 Platform Support & Downloads](#-platform-support--downloads)
- [🛠 Getting Started & Build Guide](#-getting-started--build-guide)
- [🗺 Roadmap](#-roadmap)
- [Validation and Development Docs](#validation-and-development-docs)
- [📸 Snapshots](#-snapshots)
- [💬 Community & License](#-community--license)

---

### 💡 Introduction

**Yibubang (医不帮)** is an open-source, cross-platform medical exam practice and revision software designed specifically for medical students. Traditional test preparation tools often suffer from mandatory internet connectivity, obtrusive advertisements, lack of desktop platform support, and rigid database tie-ins.

Powered by **Flutter** and engineered with an **offline-first** design philosophy, Yibubang provides a seamless, distraction-free, and blazing-fast experience across Android, Windows, macOS, Linux, and iOS/iPadOS.

With its innovative **"Split Question Banks + Globally Shared User State"** architecture, question content is strictly decoupled from user progress. While hosting hundreds of thousands of medical questions locally, all your answers, wrong problem sets, bookmarks, and activity logs remain securely stored on your own device.

---

### ✨ Key Features

- 💻 **True Cross-Platform Collaboration**
  - First-class support for Android, Windows, macOS, and Linux (iOS/iPadOS support underway).
  - Optimized keyboard shortcuts for desktop navigation and refined ergonomics for mobile devices.
- ⚡️ **Blazing Fast Startup & Zero Advertisements**
  - Instant cold launch without commercial splash screens, tracking, or mandatory logins.
  - Fingerprint and statistics caches avoid repeated scans, and hidden desktop pages mount on demand. Startup time depends on the device and first-time setup.
- 🎯 **Four Specialized Practice Modes**
  - **Practice Mode**: Immediate validation, comprehensive explanations, original exam year references, knowledge tags, and zoomable illustrations.
  - **Fast Brush Mode**: High-density question drill interface with automatic progression.
  - **Exam / Test Mode**: Simulated testing conditions with hidden answers, bottom exam navigation bar, and full diagnostic test score reports.
  - **Recitation Mode**: Displays correct answers and detailed rationales directly for rapid pre-exam memorization.
  - **Flexible Filters**: Filter by question type (single/multiple choice), cut status (all/cut/uncut), and question status (all/wrong/bookmarked/unanswered).
- 📊 **Insightful Learning Analytics & Activity Heatmap**
  - Millisecond-precision question timing (`duration`) to measure cognitive effort per question.
  - GitHub-style **practice activity heatmap** displaying daily question counts and focused study time.
  - Double-tier progress tracking (Subject & Chapter) with accuracy curves and historical timeline logs.
- 🔍 **Full-Library Parallel Search**
  - Concurrent multi-bank fuzzy querying across question stems, options, explanations, and recall tags.
  - Paged result rendering with instant jump-to-question and batch synchronization of bookmarks.
- 🔄 **Comprehensive Backup & Synchronization**
  - **Local Archive Export/Import**: Export user database into portable `.zip` bundles. Supports full replacement as well as intelligent merge (local-first answer retention, union of favorites/cut status, idempotent activity appending).
  - **Self-Hosted Cloud Sync**: Pairing-code based synchronization with a persistent change queue and sequence acknowledgments. Protocol-v2 server configuration and real-account validation remain separate work; AI conversations stay local.
  - **YKB Platform Integration**: View official question comments and community replies; offline synchronization queue for cut questions, answers, and chapter redos upon reconnecting.

---


## AI Search and Textbook Reading

AI Search sits between Daily Plan and Statistics by default. It offers streamed answers, follow-up questions, editing/retrying, stopping, copying and local conversation history. Citations open an installed question or the original textbook page.

Settings contains the built-in answer model, rephrasing, streaming, evidence count (1–25, default 12) and textbook/question split (default 8:4). Each installation has 200 allowance units per Beijing calendar day: basic answers cost 1, rephrasing 2, and rephrasing plus streaming 3. These are app allowance rules, not Google billing multipliers.

Textbook search covers 53 books and 20,669 pages with book filters, keyword highlights and thumbnails. The reader supports zoom, page navigation, retries and a 160-page offline cache. Desktop shortcuts: Shift+Enter sends a question; Left/Right turns textbook pages. Generated answers require connectivity; saved conversations and cached pages remain available offline.

The backend uses Cloud Run and Search's built-in Answer/streamAnswer. Model selection uses cached/bundled catalogs with bounded background refresh; the app does not contact Google's model documentation directly. Original PDFs stay local; clean text is indexed and private R2 serves page images. Medical facts, symbols and formulas should be checked against source pages; promotion eligibility and actual bills remain unverified.

Current source version is 2.2.4+214, user database schema25. AI conversations do not participate in cross-device sync; sync protocol-v2 server publication and real-account validation remain separate work. See [Release Notes](docs/release-notes/v2.2.4.md) for details.

[AI operations](docs/ai-search/README.md) · [Retrieval limits](docs/ai-search/RETRIEVAL_LIMITS.md) · [Costs](docs/ai-search/COSTS_AND_BUILTIN_MODELS.md) · [Current progress](docs/CURRENT_STATUS.md)

---

### 🗄 Architecture & Database Design

Yibubang adopts an SQLite storage architecture adhering strictly to **"Physical Separation of Read-Only Content and Read-Write User Data"**:

```mermaid
flowchart TD
    subgraph Remote["Remote Distribution (Gitee / CDN)"]
        UpdateJSON["yibubang_update.json\n(Bank Catalog & App Version)"]
        BankZIPs["Standalone Bank ZIPs\n(dental_final / clinical_final / nursing_final)"]
    end

    subgraph Storage["Client Local Storage (getDatabasesPath)"]
        UserData["Writable User Database\nuser_data.sqlite (Schema v25)\n• Question (Global progress/bookmarks/cut/updated_at)\n• QuestionBank (Catalog registry)\n• IdentitySubject / IdentityChapter (Per-bank stats)\n• Activities (Answer timeline & duration)\n• Notes / AiSearchSessions / AiSearchTurns / MigrationState"]

        subgraph QuestionBanksDir["QuestionBank/ Standalone Banks (Read-Only)"]
            BankDental["QuestionBank/dental_final/dental_final.sqlite\n(Dental Final ~176MB)"]
            BankClinical["QuestionBank/clinical_final/clinical_final.sqlite\n(Clinical Final ~138MB)"]
            BankNursing["QuestionBank/nursing_final/nursing_final.sqlite\n(Nursing Final ~126MB)"]
            BankCustom["QuestionBank/clinial_exam/clinial_exam.sqlite\n(Licensing Exam / Custom)"]
        end

        LegacyBackup["Fallback Backup\n• question_data.sqlite (legacy_combined fallback)"]
    end

    subgraph Memory["Application Layer (Flutter / Dart)"]
        Repo["QuestionBankRepository\n(Lifecycle, verification, atomic download)"]
        Mgr["QuestionBankDatabaseManager\n(Read-only connection pool, cache acceleration)"]
        UserHelper["UserDBHelper\n(User DB singleton, seamless migration, transactions)"]
        SearchRepo["QuestionSearchRepository\n(Multi-bank parallel search, paged merge)"]
        SyncService["RecordSyncService / CloudSyncService\n(Local intelligent merge / Cloud delta sync)"]
    end

    Remote -.->|SHA-256 Check / Stream Extract| Repo
    Repo -->|Staging Verification -> Atomic Swap| QuestionBanksDir
    Repo -->|Register / Update Catalog| UserData
    Mgr -->|Read-Only Connection| QuestionBanksDir
    UserHelper -->|Read-Write Transactions| UserData
    SearchRepo -->|Concurrent Multi-Bank Query| Mgr
    SearchRepo -->|Batch Bookmarks Fetch| UserHelper
    SyncService -->|Read-Write Export/Import| UserData
```

#### Architectural Highlights
1. **Global `question_id` Contract**: Question identities are globally unique. When a question is shared between different banks (e.g. Clinical Finals and Licensing Exam), answer progress, favorites, and cut states are shared automatically without redundant work.
2. **Atomic Upgrades & Auto-Rollback**: Bank downloads are written to `.staging` files and verified through 5-stage checks before atomic renaming. A `.bak` snapshot is created beforehand, enabling immediate fallback if any error occurs.
3. **Fingerprint Validation Cache**: Persisting file `size:modifiedMilliseconds` avoids repeated `PRAGMA integrity_check` scans when a previously verified question bank has not changed.
4. **Resilient Legacy Fail-Safe**: Existing monolithic `question_data.sqlite` files are retained as `legacy_combined` fallbacks, guaranteeing zero service interruption for long-time users.
5. **ATTACH Cross-Database Recomputation**: SQLite's `ATTACH DATABASE` aggregates question-bank content and personal statistics within the database.

> For detailed technical specifications, refer to [docs/antigravity/database_current.md](docs/antigravity/database_current.md).

---

### 📚 Supported Question Banks

| Bank ID | Official Title | Questions | Subjects | Chapters | Package Size (ZIP / Unpacked) | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `dental_final` | **Dental School Final Exam Bank** | 78,310 | 45 | 1,132 | ~32.5 MB / ~176 MB | Official Release |
| `clinical_final` | **Clinical Medicine Final Exam Bank** | 57,346 | 40 | 1,137 | ~25.9 MB / ~138 MB | Official Release |
| `nursing_final` | **Nursing School Final Exam Bank** | 69,591 | 50 | 928 | ~24.1 MB / ~126 MB | Official Release |
| `clinial_exam` | **Clinical Medical Licensing Exam** | 18,806 | 22 | 540 | ~12.0 MB / ~57 MB | Extended Bank |
| *Custom Banks* | Local User Imports (`.sqlite` / `.zip`) | Adaptive | Adaptive | Adaptive | Unlimited | Fully Supported |

---

### 📥 Platform Support & Downloads

| Operating System | Supported Architectures & Formats | Status |
| :--- | :--- | :---: |
| **Android** | `arm64-v8a`, `armeabi-v7a`, `x86_64`, `Universal APK` | ✅ Stable |
| **Windows** | `x64` Portable ZIP / Standalone Executable | ✅ Stable |
| **macOS** | `Apple Silicon (arm64)`, `Intel (x86_64)` DMG / App | ✅ Stable |
| **Linux** | `x86_64` (Tar.gz / AppImage) | ✅ Stable |
| **iOS / iPadOS** | Mobile build & codesigning testing | 🚧 In Progress |

- 📦 **GitHub Releases**: [https://github.com/nanguaguag/yibubang/releases](https://github.com/nanguaguag/yibubang/releases)
- 🚀 **Gitee Mirror (Fast Mainland China Download)**: [https://gitee.com/pumpkin_melon/yibubang/releases](https://gitee.com/pumpkin_melon/yibubang/releases)

---

### 🛠 Getting Started & Build Guide

#### Prerequisites
- [Flutter SDK](https://flutter.dev/) `>= 3.32.0`
- [Dart SDK](https://dart.dev/) `>= 3.8.0, < 4.0.0`
- Target platform build toolchains (Android Studio / Xcode / Visual Studio C++ / build-essential)

#### Build Instructions
```bash
# 1. Clone repository
git clone https://github.com/nanguaguag/yibubang.git
cd yibubang

# 2. Fetch dependencies
flutter pub get

# 3. Run in debug mode
flutter run

# 4. Build release packages
flutter build apk --split-per-abi  # Android APK
flutter build windows              # Windows Executable
flutter build macos                # macOS Bundle
flutter build linux                # Linux Binary
```

---

### 🗺 Roadmap

- [x] Multi-bank physical isolation with on-demand download & updates
- [x] High-performance parallel multi-bank search engine
- [x] Millisecond-level question duration timer and GitHub-style activity heatmap
- [x] Four study modes (Practice, Fast Brush, Exam, Recitation) with multi-criteria filters
- [x] Pre-exam quick memorization and mock exam submission report
- [x] Portable ZIP backup with intelligent two-way merge algorithm
- [x] Pairing-code sync client with persistent changes and acknowledgments
- [ ] Protocol-v2 server publication and real-account validation
- [x] AI search, streamed answers, follow-ups, local sessions and clickable source citations
- [x] Configurable built-in model, advanced options and 1–25 evidence items with source split
- [x] Textbook search across 53 books, thumbnails, zoom and offline page caching
- [x] Offline YKB synchronization queue for answers, cut questions, and chapter redos
- [x] Online community comments and reply viewer
- [x] Custom question bank importer with automated integrity validation
- [x] Font scaling (0.85x - 1.3x) and smooth dark/light theme switching
- [ ] iOS / iPadOS official bundle and codesigning documentation
- [ ] Lightweight Web-based question viewer and read-only study report portal

---

### Validation and Development Docs

Local verification with the CI SDK, Flutter 3.50.0 / Dart 3.14.0: 357 Flutter tests passed and 3 live tests skipped by default. The missing `await` flagged by CI is fixed, and the settings test avoids unrelated automatic-update networking. Both `dart analyze` and `flutter analyze --no-fatal-infos` pass with no errors or warnings and 119 deprecation infos. The earlier backend suite passed 39 tests; remote platform Actions have not been rerun.

[Documentation](docs/README.md) · [Handoff](docs/antigravity/SESSION_HANDOFF.md) · [Validation](docs/ai-search/VALIDATION.md)

---

### 📸 Snapshots

<p align="center">
  <img src="assets/images/app_image.png" alt="Desktop Question Bank Dashboard" width="48%">
  <img src="assets/images/mobile_image.png" alt="Mobile Question Interface" width="48%">
</p>
<p align="center">
  <img src="assets/images/windows_snipshot1.png" alt="Windows Question Detail View" width="48%">
  <img src="assets/images/windows_snipshot2.png" alt="Windows Study Statistics" width="48%">
</p>

---

### 💬 Community & License

- 💬 **Telegram Community Chat**: [https://t.me/yibubang](https://t.me/yibubang)
- 📄 **Open Source License**: Distributed under the [MIT License](LICENSE).
