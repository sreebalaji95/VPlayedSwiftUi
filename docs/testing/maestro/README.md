# Maestro Mobile UI Automation Suite (iOS / SwiftUI)

Automated end-to-end and input validation test flows for VPlayed 3.0 iOS (SwiftUI) using [Maestro](https://maestro.mobile.dev/).

---

## 1. Test Files Overview

| File | Purpose |
|---|---|
| [`login-input-validation-flow.yaml`](login-input-validation-flow.yaml) | Tests email input validation boundaries: empty submission, malformed patterns (`user@`, `user@example`, `user@example.c`), and valid input clearing. |

---

## 2. Prerequisites

1. Install Maestro CLI:
   ```bash
   curl -FsSL "https://get.maestro.mobile.dev" | bash
   ```
2. Boot an iOS Simulator (e.g. iPhone 17):
   ```bash
   xcrun simctl boot "iPhone 17"
   open -a Simulator
   ```
3. Build and install the `Dev` scheme to the simulator:
   ```bash
   xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```

---

## 3. Running with Maestro Studio

Open Maestro Studio in your browser for interactive inspection:
```bash
maestro studio
```
Then select `login-input-validation-flow.yaml` to run interactively.

---

## 4. Running via Maestro CLI

```bash
# Run from repository root or VPlayed directory
maestro test docs/testing/maestro/login-input-validation-flow.yaml
```
