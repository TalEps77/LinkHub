---
validationTarget: '_bmad-output/planning-artifacts/prd.md'
validationDate: '2026-05-03'
inputDocuments:
  - docs/01-project-architecture.md
  - docs/02-menubar-integration.md
  - docs/03-network-detection.md
  - docs/04-panel-ui-architecture.md
  - docs/05-ethernet-controls.md
  - docs/06-wifi-management.md
  - docs/07-state-data-management.md
  - docs/08-permissions-entitlements.md
  - docs/09-distribution-release.md
  - EXECUTION_PLAN.md
  - PLAN.md
  - README.md
validationStepsCompleted:
  - step-v-01-discovery
  - step-v-02-format-detection
  - step-v-03-density-validation
  - step-v-04-brief-coverage-validation
  - step-v-05-measurability-validation
  - step-v-06-traceability-validation
  - step-v-07-implementation-leakage-validation
  - step-v-08-domain-compliance-validation
  - step-v-09-project-type-validation
  - step-v-10-smart-validation
  - step-v-11-holistic-quality-validation
  - step-v-12-completeness-validation
  - step-v-13-report-complete
validationStatus: COMPLETE
holisticQualityRating: '4.5/5'
overallStatus: 'Pass (with minor warnings)'
---

# PRD Validation Report

**PRD Being Validated:** _bmad-output/planning-artifacts/prd.md
**Validation Date:** 2026-05-03

## Input Documents

- docs/01-project-architecture.md
- docs/02-menubar-integration.md
- docs/03-network-detection.md
- docs/04-panel-ui-architecture.md
- docs/05-ethernet-controls.md
- docs/06-wifi-management.md
- docs/07-state-data-management.md
- docs/08-permissions-entitlements.md
- docs/09-distribution-release.md
- EXECUTION_PLAN.md
- PLAN.md
- README.md

## Validation Findings

## Format Detection

**PRD Structure (Level 2 headers):**
- Executive Summary
- Project Classification
- Success Criteria
- Product Scope
- User Journeys
- Domain-Specific Requirements
- Innovation & Novel Patterns
- Desktop App Specific Requirements
- Functional Requirements
- Non-Functional Requirements

**BMAD Core Sections Present:**
- Executive Summary: Present
- Success Criteria: Present
- Product Scope: Present
- User Journeys: Present
- Functional Requirements: Present
- Non-Functional Requirements: Present

**Format Classification:** BMAD Standard
**Core Sections Present:** 6/6

## Information Density Validation

**Anti-Pattern Violations:**

**Conversational Filler:** 0 occurrences
**Wordy Phrases:** 0 occurrences
**Redundant Phrases:** 0 occurrences

**Total Violations:** 0

**Severity Assessment:** Pass

**Recommendation:** PRD demonstrates good information density with minimal violations.

## Product Brief Coverage

**Status:** N/A - No Product Brief was provided as input

## Measurability Validation

### Functional Requirements

**Total FRs Analyzed:** 58

**Format Violations:** 1
- FR42 (line 473): "The user is not subjected to a modal onboarding flow on first launch — the panel itself is the introduction." Passive form. Recast as capability: "The system can launch without modal onboarding; first panel open is the introduction."

**Subjective Adjectives Found:** 2
- FR37 (line 465): "clear feedback" — subjective. Recast: "feedback identifying the cause (wrong password / out of range / timeout)"
- FR40 (line 471): "explanatory empty state" — subjective. Already partially mitigated by following clause; tighten: "empty state identifying the cause and offering a one-tap path to Privacy settings."

**Vague Quantifiers Found:** 0

**Implementation Leakage:** 1
- FR55 (line 495): "via the standard Sparkle prompt" — names a third-party library in a capability statement. Recast as capability: "via the in-app updater dialog with cryptographic verification of the artifact." (Lock Sparkle in NFR16, not FR.)

**FR Violations Total:** 4

### Non-Functional Requirements

**Total NFRs Analyzed:** 37

**Missing Metrics:** 2
- NFR11 (line 520): "without entering a wedged state" — "wedged" is undefined. Tighten: define as "panel responsive within 1.5s of click; icon updates within 1.5s of state change after wake/reset."
- NFR23 (line 541): "meaningful `accessibilityLabel`" — subjective. Already operationalized by NFR24-NFR25; reword NFR23 as scope statement, not standalone criterion.

**Incomplete Template:** 0

**Missing Context:** 0

**NFR Violations Total:** 2

### Overall Assessment

**Total Requirements:** 95
**Total Violations:** 6

**Severity:** Warning

**Recommendation:** PRD would benefit from tightening 6 requirements flagged above. NFR implementation specificity (NFR12 Keychain attrs, NFR16 Sparkle/EdDSA, NFR17 entitlements, NFR33 Swift 6, NFR34-37 layer/class/dependency names) is intentional brownfield lockdown — not flagged. Otherwise requirements demonstrate strong measurability with explicit metrics, measurement methods, and SMART criteria throughout.

## Traceability Validation

### Chain Validation

**Executive Summary → Success Criteria:** Intact
- Vision ("single control surface for Wi-Fi + Ethernet, adaptive familiarity, icon swap moment, tight scope, native") is fully reflected in Success Criteria (User Success: replacement-grade familiarity, instant Ethernet awareness, cable-out grace, no learning curve; Technical Success: resource budget, Swift 6, accessibility; Business Success reframed as shipping/stewardship).

**Success Criteria → User Journeys:** Intact
- "Replacement-grade familiarity" → Journey 1 (Maya first-touch)
- "Instant Ethernet awareness ≤1.5s" → Journey 2 (Icon Swap)
- "Cable-out grace 1.5s" → Journey 2
- "No learning curve, ≤10s connect" → Journey 1
- "Wi-Fi password without context loss" → Journey 1, 3
- Permission recovery (implicit in Technical/User success) → Journey 4

**User Journeys → Functional Requirements:** Intact
- Journey 1 (Onboarding) → FR1-FR14 (icon/panel), FR23-FR31 (Wi-Fi list/connect), FR39-FR42 (permissions/no-modal), FR43-FR47 (login)
- Journey 2 (Icon Swap) → FR2-FR5 (icon swap timing), FR12-FR13 (panel reorder), FR15-FR20 (Ethernet rows)
- Journey 3 (Dual-Network) → FR15-FR22 (multi-Ethernet), FR23-FR38 (Wi-Fi mgmt incl. forget/inline)
- Journey 4 (Permission Denied) → FR39-FR41 (Location auth + auto-resume)
- Resource/distribution/accessibility FRs (FR48-FR58) trace to Technical Success and Business Success ("v1.0 shipped" / VoiceOver in success criteria) rather than journeys — valid traceability source.

**Scope → FR Alignment:** Intact
- All 19 must-have capabilities in scope table map to FR clusters (Capability 2/3 → FR1-FR14, Cap 4 → FR15-FR22, Cap 5/8/9 → FR23-FR38, Cap 10/11 → FR31/FR39-FR41, Cap 13 → FR48-FR50, Cap 16 → FR43-FR47, Cap 17/18 → FR51-FR55).
- Out-of-scope items (VPN, telemetry, MAS, preferences window) have no orphan FRs — scope discipline holds.

### Orphan Elements

**Orphan Functional Requirements:** 0

**Unsupported Success Criteria:** 0

**User Journeys Without FRs:** 0

### Traceability Matrix

| Source | Target | Coverage |
|---|---|---|
| Executive Summary | Success Criteria | Full |
| Success Criteria | User Journeys | Full (4 journeys cover all user-success dims) |
| User Journeys | FRs (FR1-FR47) | Full |
| Technical/Business Success | FRs (FR48-FR58) + NFRs | Full |
| Scope must-haves (19) | FRs | Full |

**Total Traceability Issues:** 0

**Severity:** Pass

**Recommendation:** Traceability chain is intact — every FR traces to a user journey or to a Technical/Business success criterion. Scope table provides explicit capability-to-PRD-source mapping, strengthening the chain further.

## Implementation Leakage Validation

### Leakage by Category

**Frontend Frameworks:** 0 violations
**Backend Frameworks:** 0 violations
**Databases:** 0 violations
**Cloud Platforms:** 0 violations
**Infrastructure:** 0 violations

**Libraries:** 2 violations (FR-level)
- FR55 (line 495): "via the standard Sparkle prompt" — third-party library name in capability statement. (Already flagged in Measurability.) Reword as "via the in-app updater dialog with cryptographic verification."
- NFR7 (line 516): "measured via Sparkle telemetry" — library name as measurement source. Acceptable in NFR (locks measurement method), borderline.

**Other Implementation Details (NFR — flagged but intentional brownfield lockdown):**
- NFR9 (line 518): "CoreWLAN delegates and SCDynamicStore callbacks" — Apple framework names. Capability-relevant since the requirement is about cleanly releasing these specific OS handles. Acceptable.
- NFR12 (line 524): `kSecClassGenericPassword` / `kSecAttrAccessibleAfterFirstUnlock` — Keychain API constants. Security NFR with measurement method; acceptable.
- NFR16 (line 528): Sparkle / EdDSA / `SUPublicEDKey` — security-critical lockdown of update mechanism. Acceptable as compliance NFR.
- NFR17 (line 529): entitlement string `com.apple.security.personal-information.location` — capability-relevant (defines exact platform permission scope).
- NFR18 (line 530): `PrivacyInfo.xcprivacy` — Apple-mandated artifact, capability-level.
- NFR33 (line 554): "Swift 6 strict concurrency" — measurable build quality criterion; acceptable.
- NFR35 (line 559): `AppState` / `EthernetMonitor` / `WiFiMonitor` class names — **architecture-doc territory**. Belongs in PRD 01/07 (architecture), not NFR. Recommend rewording to "All shared application state must flow through a single observable state container; UI must observe only that container, not source monitors."
- NFR36 (line 560): "Sparkle 2... CocoaPods, Carthage" — dependency policy. Acceptable (NFR-level constraint on dependency surface).
- NFR37 (line 561): `os.Logger` with subsystem = bundleId — observability contract; acceptable since it's the testable measurement spec.

### Summary

**Total Implementation Leakage Violations:** 2 (FR55, NFR35 architectural class names)

(Other implementation specifics scanned and judged capability-relevant or intentional NFR lockdown for brownfield desktop app — see breakdown above.)

**Severity:** Warning

**Recommendation:** Address FR55 (move Sparkle reference to NFR16 only) and NFR35 (abstract class names to architectural concept). Remaining implementation specificity is intentional brownfield lockdown of platform APIs and security mechanisms — acceptable in a desktop-app PRD where Apple frameworks and notarization details are the contract.

## Domain Compliance Validation

**Domain:** General (system/networking utility)
**Complexity:** Low
**Assessment:** N/A — No special domain compliance requirements.

PRD's "Domain-Specific Requirements" section explicitly documents the absence of regulated-domain obligations (no HIPAA, PCI-DSS, GDPR, industry certifications). External constraints listed are Apple platform requirements (notarization, privacy manifest, Location permission, Hardened Runtime) — already captured in NFRs and project-type sections.

## Project-Type Compliance Validation

**Project Type:** desktop_app

### Required Sections (per project-types.csv)

- **platform_support:** Present (line 343 — Platform Support table: macOS only, 13+ minimum, Universal binary)
- **system_integration:** Present (line 353 — System Integration table: NSStatusItem, CoreWLAN, SystemConfiguration, CoreLocation, x-apple.systempreferences URL scheme, SMAppService, Keychain, os.Logger, NSApplicationDelegate)
- **update_strategy:** Present (line 371 — Update Strategy table: Sparkle 2, EdDSA-signed appcast, user + automatic cadence, no delta updates, no rollback)
- **offline_capabilities:** Present (line 382 — Offline Capabilities subsection: fully offline by design, only Sparkle and captive-portal traffic, no telemetry/auth/remote config)

### Excluded Sections (Should Not Be Present)

- **web_seo:** Absent ✓
- **mobile_features:** Absent ✓ (PRD explicitly disclaims iOS / Windows / Linux)

### Compliance Summary

**Required Sections:** 4/4 present
**Excluded Sections Present:** 0
**Compliance Score:** 100%

**Severity:** Pass

**Recommendation:** All required sections for desktop_app are present and adequately documented. No excluded sections found.

## SMART Requirements Validation

**Total Functional Requirements:** 58

### Scoring Summary

**All scores ≥ 3:** 98% (57/58)
**All scores ≥ 4:** 91% (53/58)
**Overall Average Score:** 4.6/5.0

### Scoring (Grouped — most FRs score uniformly)

| FR Range | Specific | Measurable | Attainable | Relevant | Traceable | Notes |
|---|---|---|---|---|---|---|
| FR1–FR8 (Menu Bar Presence) | 5 | 5 | 5 | 5 | 5 | FR5 has explicit 1.5s metric; all bound to icon/state outcomes |
| FR9–FR14 (Panel Display) | 5 | 4-5 | 5 | 5 | 5 | FR13 has 1.5s grace metric; FR14 testable via OS appearance toggle |
| FR15–FR22 (Ethernet Awareness) | 5 | 5 | 5 | 5 | 5 | Multi-state interface enumeration with explicit data points |
| FR23–FR28 (Wi-Fi Discovery) | 5 | 5 | 5 | 5 | 5 | Per-network data fields enumerated |
| FR29–FR36, FR38 (Wi-Fi Connection) | 5 | 5 | 5 | 5 | 5 | Each action testable via UI flow |
| FR37 (clear feedback) | 4 | 2 | 5 | 5 | 5 | **FLAG** — "clear" subjective; measurable criterion needed |
| FR39–FR41 (Permissions) | 5 | 5 | 5 | 5 | 5 | Apple-mandated, traces to Journey 4 |
| FR40 (explanatory empty state) | 4 | 3 | 5 | 5 | 5 | borderline — "explanatory" subjective but mitigated by following clause |
| FR42 (no modal onboarding) | 3 | 3 | 5 | 5 | 5 | borderline — passive form, recast as capability |
| FR43–FR47 (Lifecycle) | 5 | 5 | 5 | 5 | 5 | Login, Dock-icon absence, retain-cycle hygiene all testable |
| FR48–FR50 (Resource Discipline) | 5 | 5 | 5 | 5 | 5 | Explicit 80MB / 0.5% / 60s window metrics |
| FR51–FR54 (Distribution & Updates) | 5 | 5 | 5 | 5 | 5 | DMG, notarization, update check — all testable |
| FR55 (Sparkle prompt) | 4 | 4 | 5 | 5 | 5 | impl leakage flagged in §Implementation Leakage |
| FR56–FR58 (Accessibility) | 5 | 5 | 5 | 5 | 5 | VoiceOver per row + state transitions |

**Legend:** 1=Poor, 3=Acceptable, 5=Excellent
**Flag:** Score < 3 in one or more categories

### Improvement Suggestions

**FR37 (Measurable=2):** "clear feedback" → Recast as: "The user can see feedback identifying the specific failure cause: wrong password / out of range / timeout / authentication error / association failure."

**FR40 (Measurable=3 borderline):** "explanatory empty state" → Tighten by removing "explanatory" — the mitigating clause already specifies content. Recast as: "The user can see an empty state identifying the cause and offering a one-tap path to the relevant Privacy settings when Location authorization is denied or restricted."

**FR42 (Specific/Measurable=3 borderline):** Recast as capability with active voice: "The system can launch without modal onboarding; the panel itself is the introduction." (Testable: no modal window appears on first launch.)

**FR55 (impl leakage):** Move "Sparkle" to NFR16 only. Recast as: "The user can install an update via the in-app update prompt, with cryptographic verification of the update artifact's authenticity."

### Overall Assessment

**Severity:** Pass (≤2% flagged; only FR37 strictly fails the < 3 threshold)

**Recommendation:** Functional Requirements demonstrate strong SMART quality overall (avg 4.6/5.0). 1 strict flag (FR37) and 3 borderline (FR40, FR42, FR55) — minor revisions recommended. Quantified metrics (1.5s, 200ms, 80MB, 0.5%, 99.5%, 7 days) are present throughout, anchoring testability.

## Holistic Quality Assessment

### Document Flow & Coherence

**Assessment:** Excellent

**Strengths:**
- Strong narrative arc: Executive Summary → "What Makes This Special" → Project Classification → Success Criteria (User / Business / Technical / Measurable Outcomes table) → Product Scope (must-have / nice-to-have / out-of-scope / growth / vision / risk mitigation) → User Journeys (4 narrative scenarios with named personas + revealed requirements) → Domain (deliberately N/A with rationale) → Innovation (deliberately N/A with rationale) → Project-Type (Platform / Integration / Update / Offline / Code Signing / Implementation Considerations) → FRs grouped by feature cluster → NFRs grouped by quality attribute.
- Self-aware about scope: out-of-scope list, "Saying no to them is the product," disqualifier framing of nice-to-haves.
- Risk Mitigation tables enumerate likelihood and mitigation per technical / market / resource risk.
- User Journeys use "Reveals requirements" footers that pre-trace journey → PRD source — strengthening downstream LLM consumption.
- Measurable Outcomes table consolidates SLOs in one scannable place.

**Areas for Improvement:**
- "Innovation & Novel Patterns" and "Domain-Specific Requirements" sections deliberately N/A — well-justified prose, but the BMAD validator could mistake them for missing content; current text handles this cleanly.
- Implementation Considerations subsection (line 403) blurs PRD/architecture boundary slightly — could be moved to PRD 07 (architecture) or labeled as "PRD-locked architectural constraints."

### Dual Audience Effectiveness

**For Humans:**
- Executive-friendly: Strong. Executive Summary + "What Makes This Special" reads as elevator pitch + differentiation in <2 minutes.
- Developer clarity: Strong. FRs are crisp capability statements; NFRs lock specific platform contracts; PRDs 01–09 cited inline as authoritative sources.
- Designer clarity: Strong. User Journeys show layout intent (Ethernet-on-top, inline password expansion, empty-state recovery); explicit "match Apple's HIG / live system Wi-Fi menu" reference removes ambiguity.
- Stakeholder decision-making: Strong. Out-of-scope list + risk tables + measurable outcomes give a stakeholder enough to approve / amend / reprioritize.

**For LLMs:**
- Machine-readable structure: Strong. Consistent ## L2 headers, FR/NFR numbering, frontmatter classification.
- UX readiness: Strong. Journeys + layout contract (Ethernet above Wi-Fi when link present) + empty-state spec are sufficient to generate UX flows.
- Architecture readiness: Strong. NFR12, NFR16, NFR17, NFR18, NFR33–NFR37 plus Implementation Considerations explicitly lock the architecture surface; PRDs 01–09 referenced as backing detail.
- Epic/Story readiness: Strong. 19-row scope table maps capability → backing PRD; FRs cluster naturally into epics (Menu Bar, Panel, Ethernet, Wi-Fi Discovery, Wi-Fi Connection, Permissions, Lifecycle, Resource Discipline, Distribution, Accessibility).

**Dual Audience Score:** 5/5

### BMAD PRD Principles Compliance

| Principle | Status | Notes |
|-----------|--------|-------|
| Information Density | Met | 0 filler/wordy/redundant phrases detected. |
| Measurability | Met | 6 minor flags out of 95 reqs; quantified metrics throughout. |
| Traceability | Met | 0 orphan requirements; explicit journey → FR → PRD trail. |
| Domain Awareness | Met | General domain explicitly justified; Apple platform constraints documented. |
| Zero Anti-Patterns | Partial | 2 subjective adjectives (FR37 "clear", FR40 "explanatory"), 1 passive form (FR42), 1 library-name in FR (FR55), 1 architectural-class-name in NFR (NFR35). |
| Dual Audience | Met | Strong for both human reviewers and downstream LLM consumers. |
| Markdown Format | Met | Clean L2 headers, tables, frontmatter, ordered FR/NFR numbering. |

**Principles Met:** 6/7 fully, 1 partial

### Overall Quality Rating

**Rating:** 4.5/5 — between Good and Excellent

Rationale: PRD demonstrates exemplary structure, traceability, scope discipline, and dual-audience clarity. A handful of micro-revisions (FR37, FR40, FR42, FR55, NFR35) would push it to 5/5 / Excellent.

### Top 3 Improvements

1. **Tighten the 4 measurability/leakage flags into capability-clean phrasing.**
   FR37 (specify failure causes), FR40 (drop "explanatory"), FR42 (recast in active voice), FR55 (move Sparkle to NFR16). Low effort, raises every FR above the SMART <3 threshold.

2. **Abstract NFR35 from class names to architectural concept.**
   "All shared application state must flow through a single observable state container; UI must observe only that container, not the source monitors." Class names belong in PRD 07 (architecture). Same for the "Implementation Considerations" subsection — consider relocating to PRD 07 or flagging it explicitly as PRD-locked architectural constraint.

3. **Add a one-line capability statement to the "Innovation & Novel Patterns" and "Domain-Specific Requirements" N/A sections.**
   Currently both are well-justified prose. A leading single-line summary ("Status: N/A — rationale: …") would help LLM consumers detect the deliberate exclusion immediately rather than parsing a paragraph.

### Summary

**This PRD is:** A near-exemplary brownfield desktop-app PRD — tight scope thesis, fully traceable from vision to FRs, strong dual-audience clarity, and disciplined about what it refuses to include.

**To make it great:** Focus on the top 3 improvements above.

## Completeness Validation

### Template Completeness

**Template Variables Found:** 0 — no `{var}`, `{{var}}`, `[TBD]`, `[TODO]`, or unfilled template placeholders remain.

(Note: `PLACEHOLDER_TEAM_ID` appears in Risk Mitigation table line 214 as a deliberate, documented build-time signing-cert placeholder — not a PRD authoring gap.)

### Content Completeness by Section

- **Executive Summary:** Complete (vision + target user + "What Makes This Special" 4-point differentiation)
- **Success Criteria:** Complete (User / Business / Technical / Measurable Outcomes table)
- **Product Scope:** Complete (Strategy, 19-row Must-Have, Nice-to-Have, Out-of-Scope, Growth, Vision, Risk Mitigation)
- **User Journeys:** Complete (4 journeys with named personas Maya / Yossi / Itai + Reveals-Requirements footers + summary capability cluster table)
- **Functional Requirements:** Complete (58 FRs across 10 feature clusters)
- **Non-Functional Requirements:** Complete (37 NFRs across 6 quality attributes)
- **Domain-Specific Requirements:** Complete (deliberately N/A with rationale)
- **Innovation & Novel Patterns:** Complete (deliberately N/A with rationale)
- **Desktop App Specific Requirements:** Complete (Project-Type Overview, Platform Support, System Integration, Update Strategy, Offline Capabilities, Code Signing & Distribution, Implementation Considerations)

### Section-Specific Completeness

- **Success Criteria Measurability:** All — 9-row Measurable Outcomes table consolidates SLOs (1.5s / 80MB / 0.5% / 200ms / 100ms / 0 warnings / 99.5% / 10s).
- **User Journeys Coverage:** Yes — covers onboarding (Maya), aha-moment / dual-network (Maya, Yossi), permission-denied recovery (Itai). Three distinct persona archetypes (developer, video editor, designer-new-to-macOS).
- **FRs Cover MVP Scope:** Yes — 19 must-have capabilities all map to FR clusters (verified in Traceability §).
- **NFRs Have Specific Criteria:** All — every NFR has a measurement method or testable contract (NFR1–NFR8 timing/perf, NFR9–NFR11 cleanup/reliability, NFR12–NFR18 security, NFR19–NFR22 privacy, NFR23–NFR28 accessibility, NFR29–NFR33 compatibility, NFR34–NFR37 maintainability).

### Frontmatter Completeness

- **stepsCompleted:** Present (12 PRD-creation steps logged)
- **classification:** Present (projectType, domain, complexity, projectContext)
- **inputDocuments:** Present (12 docs)
- **date:** Present in body (`**Date:** 2026-05-03`, line 46) — not in frontmatter, but accessible. Minor.
- **releaseMode:** Present (single-release)
- **workflowType:** Present (prd)

**Frontmatter Completeness:** 4/4 critical fields present (date in body counts).

### Completeness Summary

**Overall Completeness:** 100% (9/9 sections complete)

**Critical Gaps:** 0
**Minor Gaps:** 1 — `date` lives in body rather than frontmatter (cosmetic).

**Severity:** Pass

**Recommendation:** PRD is complete with all required sections and content present. Optional cosmetic improvement: surface `date: '2026-05-03'` in frontmatter for machine-readability.
