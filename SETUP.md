# FinanceTracker — Setup Guide

## 1. Supabase Project

1. Go to https://supabase.com and create a new project (free tier is fine).
2. In the **SQL Editor**, open `Supabase/schema.sql` from this repo and run it.
3. Go to **Authentication → Providers → Email** and **disable email confirmation** (toggle off "Confirm email") so you can sign in immediately without verifying.
4. Copy your credentials from **Project Settings → API**:
   - `Project URL`
   - `anon` public key

---

## 2. Wire Up Credentials

Open `FinanceApp/Services/SupabaseClient.swift` and replace the two placeholder strings:

```swift
static let url     = "https://YOUR_PROJECT_REF.supabase.co"
static let anonKey = "YOUR_SUPABASE_ANON_KEY"
```

---

## 3. Create the Xcode Project

1. Open **Xcode → File → New → Project**
2. Choose **iOS → App**
   - Product Name: `FinanceApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - **Uncheck** "Include Tests" (optional)
3. Save it inside `~/FinanceApp/` (replace the auto-generated `FinanceApp` folder with ours, or just copy files in).

### Delete the default file
Remove `ContentView.swift` that Xcode generated — our `FinanceApp.swift` replaces it.

---

## 4. Add Supabase Swift SDK

1. In Xcode: **File → Add Package Dependencies…**
2. Paste URL: `https://github.com/supabase/supabase-swift`
3. Choose **Up to Next Major Version** from `2.0.0`
4. Add **Supabase** to your app target.

---

## 5. Add All Source Files

Drag the entire `FinanceApp/` source folder into your Xcode project navigator.
Make sure **"Copy items if needed"** is unchecked (files are already in the right place)
and your app target is checked.

The folder structure to add:

```
FinanceApp/
├── App/            ← FinanceApp.swift, AppState.swift
├── Services/       ← SupabaseClient + 3 services
├── Models/         ← 5 model files
├── ViewModels/     ← 3 view model files
├── Views/
│   ├── Auth/       ← AuthGateView, LoginView, SignUpView
│   ├── Main/       ← MainTabView
│   ├── Dashboard/  ← DashboardView
│   ├── Transactions/
│   ├── Savings/
│   ├── Settings/
│   └── Components/ ← TransactionRow, AccountCard, SavingsGoalCard
└── Utilities/      ← Color+Hex, LocalCache
```

---

## 6. Build & Run

- Select your iPhone or the iOS Simulator.
- Press **⌘R** to build and run.
- Sign up with your email → add an account in Settings → start tracking!

---

## 7. TestFlight (when ready)

1. Set your **Bundle Identifier** in Xcode (e.g. `com.yourname.financetracker`).
2. Set your Apple Development **Team** under Signing & Capabilities.
3. **Product → Archive**, then upload via the Xcode Organizer.
4. In App Store Connect, add yourself as an **internal tester** under TestFlight.

---

## Feature Overview

| Screen       | What it does |
|---|---|
| Dashboard    | Total balance card, monthly income/expenses/savings, account tiles, recent transactions |
| Transactions | Full list with Income/Expense/All filter, swipe to delete, + button to add |
| Savings      | Goal cards with animated progress bars, tap to contribute money |
| Settings     | Manage accounts (add / delete), profile info, sign out |

## Data Flow

```
SwiftUI View  ←→  @Observable ViewModel  ←→  Service (async/await)  ←→  Supabase
```

All network calls are `async throws`. Pull-to-refresh reloads data. Offline, the
app shows whatever was last loaded in memory (LocalCache available for extension).
