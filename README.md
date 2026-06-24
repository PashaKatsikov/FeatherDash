# Feather Dash 🐔🏀

A vertical Android arcade game built with Flutter. Inflate a chicken with a pump and
launch it through basketball hoops — but don't over-inflate, or it pops!

## Gameplay

- **Aim & inflate**: drag back from the chicken (slingshot style). The further you pull,
  the more the chicken inflates (`usual → slightly puffed → puffed`) and the more power
  you get. Pull too far and the chicken **explodes** — attempt wasted.
- **Score**: launch the chicken cleanly through a hoop's rim and net. Harder hoops
  (smaller, higher, moving) award more points.
- **Levels**: 40 levels, easy → hard. Each has a time limit and a target score. More
  hoops and moving hoops appear in later levels.
- **Coins & Shop**: earn coins by clearing levels and spend them on:
  - **Courts** – background arenas
  - **Pumps** – higher launch power
  - **Skins** – cosmetic chicken looks (each with its own inflate/explode art)

## Features

- Strictly **portrait** gameplay (in English).
- Loading screen that supports **both portrait and landscape**, with a left-to-right
  progress bar that completes only right before launch, plus an animated `Loading...` label.
- **Privacy Policy** and **Support** pages opened in an in-app WebView.
- Adaptive, full-bleed launcher icon.
- Custom-painted basketball **hoop + net** so the chicken passes cleanly through.

## Tech

- Flutter (Material 3), custom game loop via `Ticker`.
- `shared_preferences` for progress (coins, unlocked levels, owned/selected items, stars).
- `webview_flutter` for Privacy/Support.
- `flutter_launcher_icons` for the adaptive icon.

Bundle id: `com.frenzyfeath.featherdash`

## Project structure

```
lib/
  main.dart                 # App entry, theme, shared widgets
  game_data.dart            # Assets map, shop items, 40 level generator, persistent state
  widgets/hoop.dart         # Custom-painted backboard + rim + animated net
  screens/
    loading_screen.dart     # Splash with progress bar (portrait/landscape)
    menu_screen.dart        # Main menu
    level_select_screen.dart# 40-level grid
    shop_screen.dart        # Courts / Pumps / Skins
    game_screen.dart        # Core gameplay
    webview_screen.dart     # Privacy / Support
```

## Run

```bash
flutter pub get
flutter run                 # debug on a connected device/emulator
flutter build apk --release # release APK
```

> Note: `kotlin.incremental=false` is set in `android/gradle.properties` to avoid a
> Kotlin cache-locking issue on Windows.
