# LinkHub

A macOS menu bar app that replaces the standard Wi-Fi menu with a unified control center for both Wi-Fi and Ethernet.

## What it does

- **No Ethernet connected** — behaves identically to the built-in Wi-Fi menu bar item. A note at the bottom of the panel reads "No Ethernet connection detected."
- **Ethernet connected** — the menu bar icon switches from the standard Wi-Fi symbol to an Ethernet-style icon. The panel shows Ethernet status and controls first, followed by available Wi-Fi networks and Wi-Fi controls below.

## Why

macOS has no single place to manage both wired and wireless network connections. You get a Wi-Fi menu or you open System Settings. LinkHub gives you one control surface that handles both, without losing the familiarity of the existing Wi-Fi menu when Ethernet isn't in use.

## Status

Planning phase — see [PLAN.md](PLAN.md) for progress.

## Stack

- Swift
- SwiftUI / AppKit
- CoreWLAN
- SystemConfiguration
- macOS 13+
