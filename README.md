<p align="center">
  <img src="SmartClip/Resources/AppIcon.icns" width="128" alt="SmartClip icon" />
</p>

<h1 align="center">SmartClip</h1>

<p align="center">
  A lightweight, native macOS clipboard manager that lives in your menu bar.
</p>

<p align="center">
  <a href="https://github.com/sompodsign/smart-clip/releases/latest"><img src="https://img.shields.io/github/v/release/sompodsign/smart-clip?style=flat-square" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/sompodsign/smart-clip?style=flat-square" alt="License" /></a>
</p>

---

## ✨ Features

- **Menu-bar app** — always one click away, no Dock icon clutter
- **Clipboard history** — automatically captures text, rich HTML, and images
- **Instant search** — fuzzy filter across your entire clipboard history
- **Content type filters** — quickly narrow down to text, links, or images
- **Pin items** — keep frequently used snippets at the top
- **Source app tracking** — see which app each clip came from
- **Image thumbnails** — visual previews for copied images
- **Configurable history limit** — choose how many items to keep
- **Plain-text mode** — strip formatting when pasting
- **Auto-updates** — stay current via [Sparkle](https://sparkle-project.org/)
- **Freemium licensing** — free tier (5 items) with a Pro unlock for unlimited history

## 📦 Install

### Homebrew (recommended)

```bash
brew install sompodsign/tap/smartclip
```

### Manual download

Grab the latest `.dmg` from [**Releases**](https://github.com/sompodsign/smart-clip/releases/latest), open it, and drag **SmartClip.app** to your Applications folder.

## 🛠 Build from source

> Requires **macOS 14+** and **Swift 5.9+**.

```bash
# Clone the repo
git clone https://github.com/sompodsign/smart-clip.git
cd smart-clip

# Resolve dependencies & build
swift package resolve
swift build -c release

# Or use the included helper
./build.sh
```

The built `.app` bundle will be at `SmartClip.app/`.

## 🏗 Architecture

```
SmartClip/
├── Models/              # Data models (ClipboardItem, LicenseState)
├── Views/               # SwiftUI views (ContentView, ItemCard, SearchBar, …)
├── ViewModels/          # ClipboardViewModel — MVVM driving the UI
├── Services/            # Core services
│   ├── ClipboardMonitor # Polls NSPasteboard for new entries
│   ├── DatabaseService  # SQLite persistence via GRDB
│   ├── ImageService     # Thumbnail generation & caching
│   ├── KeychainService  # Secure license key storage
│   └── LicenseService   # Freemium activation & validation
├── Utilities/           # KeyablePanel, ImageCache, helpers
└── Resources/           # App icon & bundled assets
```

**Key dependencies:**

| Package | Purpose |
|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database layer |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | In-app auto-updates |

## 🚀 Release workflow

Pushing a version tag triggers the CI pipeline:

```bash
./release.sh          # bumps version, creates & pushes a git tag
```

The [GitHub Actions workflow](.github/workflows/release.yml) then:

1. Builds universal binaries (arm64 + x86_64)
2. Bundles `.app` and creates signed `.dmg` installers
3. Uploads to GitHub Releases (draft) and Google Cloud Storage
4. Updates the Homebrew cask with the new version & SHA

## 📄 License

See [LICENSE](LICENSE) for details.
