# Space Explorer

A SwiftUI iOS app for browsing SpaceX launches and rockets. Uses native Liquid Glass on iOS 26+, Swift 6 concurrency, Observation, URLSession, and XCTest. No third-party dependencies.

## Run

1. Open `SpaceXExplorer.xcodeproj` in Xcode 26 or newer.
2. Select the shared **SpaceXExplorer** scheme and an iOS 26+ simulator.
3. Run. Open **Settings → Data source → Demo data** for an immediate, deterministic walkthrough, or add `--demo` to the scheme's launch arguments.
4. To run on a physical device, choose your development team and a unique bundle identifier in Signing & Capabilities. No signing identity is committed.

This build was compiled with Xcode **27.2 beta (27B5019j)**. The code targets iOS 26 APIs; compatibility with a stable Xcode release has not yet been verified.

## API fallback

The app uses the SpaceX API with local mock data as a fallback when the service is unavailable. Live checks on September 20, 2026 returned HTTP 525 for launches and rockets. The upstream repository is archived.

| Mode | Behavior |
| --- | --- |
| Automatic (default) | Try the live API. On failure, prefer an exact cached query. If there is no cache and the failure indicates unavailability, use clearly labeled demo data. |
| Live API only | Uses the network and existing live cache; never substitutes demo records. |
| Demo data | Loads bundled JSON without making SpaceX API requests. Remote example images may still load; local artwork appears without a connection. |

**Demo content is illustrative, not current SpaceX data.** There are 24 fictional missions and four illustrative rocket records. Synthetic IDs prevent confusion with API records. Mission dates span 2026 into early 2027 and remain fixed for reproducible filtering. Upcoming status follows the fixture's API flag, not the device clock. Specifications and success percentages are example values. The example video and photo show a historical mission, not the fictional mission/rocket displayed.

Demo JSON is never written into the live cache. Each paginated list stays on its selected data source until a refresh; a failed live page two cannot append demo records. A malformed successful response surfaces as an error instead of being silently replaced with samples.

## Features

- Launches and Rockets tabs with independent navigation stacks.
- Paginated launch list: mission, site, UTC date, and explicit status.
- All / Past / Upcoming controls and inclusive start/end day filtering.
- Launch details with description, image/fallback artwork, launch site, date, status, video link, and rocket card.
- Paginated rocket list with images, names, types, and success rates.
- Shared rocket details with description, active state, engine count, and engine type.
- Pull to refresh, retry actions, empty states, nonblocking refresh errors, and page-specific retry.
- Dynamic Type, semantic status labels, system colors, and native Liquid Glass bars/sheets. Custom artwork is decorative; image accessibility describes missing imagery.

Pagination uses an explicit **Load more** button. This keeps page failures easy to retry, works with VoiceOver, and makes both paginated flows easy to demonstrate. Launch pages contain eight items; rocket pages contain two so the small demo fleet visibly exercises pagination.

## Architecture

```text
App/                  SwiftUI composition, feature screens, shared UI and image loading
Core/                 Local Swift package; Foundation/Observation, no SwiftUI dependency
  Sources/SpaceXCore/  Domain types, DTO mapping, API, fixtures, repository, cache, page model
  Tests/              Deterministic XCTest coverage
UITests/              Simulator navigation/filter/pagination smoke tests
docs/                 Decisions and manual verification checklist
```

`View → @MainActor @Observable PageModel → SpaceXRepository → SpaceXService / DiskCache`

The reusable page model owns pagination and presentation state. Feature views own their query and task lifecycle. The repository handles source selection and persistence; API DTOs map into immutable domain models. Constructor injection supplies live services, fixtures, cache directories, and a clock. Protocols exist at the service boundary where substitution is useful; there is no dependency container or use-case wrapper per endpoint.

See [architecture decisions](docs/Architecture.md) for tradeoffs and edge cases.

## Offline and caching

- Cached first pages appear before revalidation. Every list refresh attempts the API; there is no freshness interval that suppresses explicit refreshes.
- A failed or canceled refresh keeps visible content and its pagination cursor. Cached results include the original fetch time.
- Query cache keys include the date/period filter, sort implied by period, page, and page size. Record schema version is validated on read.
- Successful first-page refresh invalidates the older page chain for that query. Query generations prevent obsolete in-flight responses from writing those pages back into the cache.
- Cache files are atomic, actor-isolated, capped at 100 entries / 10 MB, and stored in the app's disposable Caches directory. Corruption becomes a cache miss. Persistence errors do not discard a successful network response.
- Previously loaded rocket list records are cached individually for detail navigation.
- Offline access covers fetched pages/details only. An uncached query in live-only mode reports failure, not an empty result. Automatic mode may instead show the visibly labeled demo dataset.
- Images have separate bounded memory/disk caches and coalesced requests. Image decoding/downsampling happens outside the main actor. Unavailable imagery uses local artwork; image failures never block details.
- Retry via pull to refresh or the visible retry button after reconnection. There is no background polling or reachability gate. Video links need network access.

## Tests

Core tests run without a simulator or network:

```sh
swift test --package-path Core
```

Run the three UI smoke tests with Product → Test in the app scheme, or:

```sh
xcodebuild test -project SpaceXExplorer.xcodeproj \
  -scheme SpaceXExplorer -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID'
```

Unsigned app build:

```sh
xcodebuild build -project SpaceXExplorer.xcodeproj \
  -scheme SpaceXExplorer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

To select a beta without changing the system-wide Xcode selection, prefix the command with `DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer`.

**Verified here:** 35 core XCTest tests passed; unsigned iOS device and Simulator builds, including UI test bundle compilation (`build-for-testing`), succeeded. Core coverage includes HTTP status/decoding/transport handling, DTO mapping, fixture pagination, date boundaries and DST, demo/live isolation, cache persistence/corruption, stale page invalidation, cancellation, duplicate page requests, and late responses. Regression coverage also verifies pagination recovery after failed/canceled refreshes, obsolete cache-write rejection for launch and rocket pages, overlapping first-page refreshes, and independent query generations.

**Not yet verified:** simulator execution, UI smoke tests, visual/accessibility inspection on a running device, and live success responses from the unavailable upstream service. The local session could not connect to CoreSimulator. See the [manual checklist](docs/Verification.md). UI tests are committed but are not reported as passed.

The GitHub Actions workflow runs core tests and compiles the app/UI test bundle for the simulator SDK using the runner's selected Xcode. It requires Xcode 26+.

## References and assets

- [SpaceX API repository](https://github.com/r-spacex/SpaceX-API)
- [Query and pagination contract](https://github.com/r-spacex/SpaceX-API/blob/master/docs/queries.md)
- [Apple: adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- Remote example imagery/video URLs are taken from the SpaceX API README's historical Crew Dragon demo launch example. They remain hosted by their original providers and may become unavailable. No third-party photographs are bundled.
- App icon and fallback artwork are original geometric illustrations. No SpaceX logo is included.

This project is not affiliated with SpaceX.
