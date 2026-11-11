<div align="center">

# MimoDays

**Little moments. Your whole life.**

A private memory journal for iPhone and iPad. MimoDays surprises you at random moments and invites you to capture a small slice of ordinary life: what you see and your own face in the same frame. Over the years, the pieces add up to a timeline, a map and personal movies.

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B%20%7C%20iPadOS%2018%2B-4B2938?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6-F06446?style=flat-square&logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI-F5AD5E?style=flat-square)
![Data](https://img.shields.io/badge/data-SwiftData-B6CCAA?style=flat-square)
![Status](https://img.shields.io/badge/status-in%20development-DFE9D0?style=flat-square)

</div>

---

> We photograph the special days. MimoDays remembers the ordinary ones, too.

## Why

Most of life happens on days nobody thinks to document. MimoDays exists for those days. You don't plan or stage anything, and there are no streaks to protect: a gentle surprise arrives, you capture what's there (or skip it), and the moment goes into your archive.

## What it does

| | |
|---|---|
| **Surprise prompts** | Random local reminders within the hours and days you choose. Skip any of them, guilt-free |
| **Dual-camera capture** | The world through the rear camera, you through the front one in a small picture-in-picture frame. Photo or short video, with a single-camera fallback |
| **Notes and voice** | Add a sentence or a voice note, or save without a word. Time is recorded automatically and location is optional |
| **Memories** | Timeline, calendar, search, favorites, collections and On This Day |
| **Map** | Revisit the places where moments happened, only for moments you chose to tag |
| **Movies** | Turn a month, a year or any selection into a movie, automatically or by hand |
| **Your data, portable** | Export single moments, selections, movies or the whole archive, and restore it on a new device |

> Everything above is the target for the first public release. The app is in active development, and features land in dependency order: capture and storage first, then archive, map, movies, export and backup.

## Principles

- **Private by default.** Media stays on the device. No account, no feed, no followers, no likes.
- **No guilt.** Missing a prompt is normal and never punished.
- **Fast capture.** From notification to saved moment in a few taps, with no required caption.
- **Durable.** Originals are never modified destructively. Archives are versioned and checksummed.
- **Accessible.** Dynamic Type, VoiceOver, Reduce Motion, and large touch targets everywhere.

## Tech stack

| Area | Technology |
|---|---|
| UI | SwiftUI (UIKit where the camera or editor needs it) |
| Language | Swift 6, strict concurrency |
| Persistence | SwiftData for metadata, files on disk for media |
| Camera | AVFoundation, `AVCaptureMultiCamSession` with a single-camera fallback |
| Movies | AVFoundation compositions |
| Reminders | UserNotifications (local only) |
| Places | CoreLocation and MapKit |
| Tests | Swift Testing, XCUITest, snapshot tests |

## Requirements

- Xcode with the iOS 18 SDK or newer
- iOS / iPadOS 18.0+
- A physical iPhone with multi-camera support to try dual-camera capture. The simulator and older devices use the single-camera path

## Getting started

```bash
git clone git@github.com:Dronnn/mimodays-ios.git
cd mimodays-ios
open MimoDays.xcodeproj
```

Select the `MimoDays` scheme, pick a simulator or device, and run. To run on a device, set your own development team under *Signing & Capabilities*.

## Quality

The project is meant to be maintained for years, so testability is treated as a design constraint, not an afterthought:

- **Unit tests** for scheduling, time zones, selection algorithms and storage logic
- **Integration tests** against an in-memory SwiftData store and a temporary file system
- **UI tests** for every core flow, driven by seeded data and fake system services
- **Snapshot tests** for every screen state in light/dark, compact/regular, iPhone/iPad and large Dynamic Type
- **Accessibility audits** as part of the UI test suite

## Project structure

```text
MimoDays/            App sources
MimoDaysTests/       Unit and integration tests
MimoDaysUITests/     UI and flow tests
```

The structure grows feature by feature as the app takes shape.

## Related

- [mimodays-website](https://github.com/Dronnn/mimodays-website) - the promotional website

## License

Copyright (c) 2026 Andrew Maier. All rights reserved.

The source is public so people can read it. It is not licensed for reuse, redistribution, or publishing derivative apps.
