# PRD 02 — Menu Bar Integration

**Status:** ⬜ Not Started  
**Depends on:** 01  
**Blocks:** 04

---

## Problem Statement

> How should LinkHub integrate with the macOS menu bar — lifecycle of the NSStatusItem, panel presentation approach, icon asset strategy, and the trigger contract for switching between Wi-Fi and Ethernet icons?

This PRD must decide:

- **NSStatusItem lifecycle** — where and how the status item is created, retained, and torn down; what happens on login-item launch vs. normal launch
- **Panel presentation** — `NSMenu` (native dropdown) vs. custom `NSPanel`/`NSPopover` attached to the status item; how the popover is dismissed (click-outside, Escape, second click on icon)
- **Icon asset pipeline** — SF Symbols (system-provided, adaptive) vs. custom vector assets in `Assets.xcassets`; how icon variants (Wi-Fi, Ethernet, mixed/both active, disconnected) are named and stored
- **Icon-swap trigger contract** — the exact signal (event type, data shape, caller) that causes the status item image to switch between Wi-Fi and Ethernet representations; who owns this logic
- **Accessibility** — `accessibilityLabel` values for the status item in each state; VoiceOver announcement strategy when the icon changes

## Decision Log

| Decision | Options Considered | Choice | Rationale |
|----------|--------------------|--------|-----------|

## Constraints

## Out of Scope

## Open Questions

## References
