# Architecture decisions

## Build architectures

Debug uses `ONLY_ACTIVE_ARCH = YES`, matching Swift Package Manager's Debug behavior for a selected simulator. The app and Core package therefore build for the same destination architecture. Release uses `NO`. CI explicitly overrides the setting to `NO` for all targets, including packages, to compile both simulator architectures in its generic-destination build. Neither architecture is excluded or hardcoded.

## Small, feature-based MVVM

Four screens do not need a navigation framework, global state store, or a use-case class for each request. SwiftUI owns navigation and feature queries. A generic observable page model centralizes the difficult shared mechanics; the repository keeps data-source decisions out of views. The local Core package makes behavior testable without a simulator.

An intentional simplification: screen state uses a content array plus orthogonal loading/error properties rather than a single enum. Refreshing and page failure can coexist with visible content. Only model methods mutate this state, and tests exercise those transitions. If feature-specific state grows substantially, introduce dedicated Launches/Rockets models around this shared pagination component.

## API contract

- `POST /v5/launches/query`, with populated launchpad and rocket name/type.
- `POST /v4/rockets/query` for paginated rocket specifications.
- `GET /v4/rockets/{id}` for details.
- Date filtering uses `$gte` at the first selected day's UTC midnight and `$lt` at the following day's UTC midnight. Calendar arithmetic avoids assumptions about day length.
- Launches sort descending by date except Upcoming, which sorts ascending. `_id` provides a stable tie breaker. Client deduplication handles overlapping pages, but the server does not offer snapshot pagination; changing live datasets may still shift page boundaries.
- Server `upcoming` and nullable `success` determine status. A null success is Unknown, not Failed. Approximate date precision is respected in presentation.
- Populated relations and ID-only references both decode; missing relations are displayed honestly. Only HTTPS links are exposed to views.

URLSession has a 12-second request timeout. Requests can be canceled through SwiftUI task lifetime. Cancellation is never presented as a network error and never triggers demo fallback. There is no automatic retry loop: explicit retry avoids multiplying outage traffic or obscuring the transition to demo mode. A production extension could add bounded retries with Retry-After support for 429/503.

## Source selection

Automatic fallback order is live response → exact saved query → demo for availability failures. Contract errors remain visible. Cached results may be returned alongside the refresh error, so the user sees both useful data and the failure.

The page model sends the selected source on subsequent pages. The repository will not switch a live chain to demo. A rocket opened from a demo launch must resolve from demo, even if the network recovers. Source changes happen on first-page refresh or an explicit Settings mode change. Changing mode reconstructs the root dependency graph and clears the navigation context.

## Concurrency and cache

Domain values are Sendable; UI mutation is MainActor-isolated. Repository and cache actors protect mutable state. The API client performs decoding outside the UI actor under Swift 6's standard nonisolated async execution behavior. No detached task is used for screen state.

Screen generation tokens prevent an old query or page response from changing newer visible state. Task cancellation is checked at repository and presentation boundaries. A cache read precedes network revalidation; refresh never blanks useful rows. Only one load-more request per page model may execute at a time.

File snapshots suit a read-only assignment. They are intentionally not an offline database. SwiftData would be a better fit for favorites, edits, or complete offline query support. No synchronization queue or migration framework is needed for disposable versioned cache records.

The image pipeline isolates disk work and downsampling from the UI, coalesces downloads, and bounds retained memory/disk data. Cached images use URL identity and remain until eviction; remote image revalidation/ETag handling is a possible future improvement. Shared image requests can finish after one cell disappears so other cells can reuse them.

## Scope and extensions

The first implementation prioritizes complete flows and deterministic failure behavior. Potential subsequent iterations, after runtime UI validation:

- Add an API contract test against a restored endpoint.
- Add deterministic offline UI scenarios using an injected transport failure.
- Add foreground/reconnection-triggered refresh if desired; currently retry is user-driven.
- Replace illustrative fixtures with an attributed historical API snapshot approved by the team.
- Add richer navigation restoration and universal links if required.

Avoid expanding the architecture solely to demonstrate patterns. The current boundaries correspond to concrete responsibilities and test seams.
