# Runtime verification checklist

Core tests, the unsigned device build, and UI test bundle compilation are verified. These runtime checks remain to be performed on an iOS 26+ simulator or device.

## Demo walkthrough

1. Set `--demo` as a launch argument, or choose Demo data in Settings.
2. Confirm the Sample data banner. Open the newest mission, scroll to its rocket card, and open Rocket details.
3. Return to Launches, load subsequent pages, and confirm 24 total rows without duplicates.
4. Switch to Upcoming and confirm seven records in ascending date order.
5. Apply Jan 1–Jan 31, 2026 in All; verify only dates in the selected interval. Choose a range outside the fixture dates; verify the empty state. Try an invalid end date; verify validation.
6. Open Rockets, load the second page, and open all four rocket details.
7. Confirm the video link is explicitly an example in demo mode. Upcoming fixtures omit the video.

## Failure and offline behavior

1. In Automatic, let the unavailable API fall back to demo with an explanatory banner.
2. Switch to Live API only with an empty cache. Confirm an error and retry, not silent demo content.
3. With a working API or a controlled test server, fetch pages and rocket details; relaunch offline and confirm cached content and the original timestamp.
4. Fail a later page; existing rows must remain with a page-level retry.
5. Change date filters during a delayed request; only the final query should be displayed.
6. Restore connectivity and pull to refresh. Confirm a successful live response replaces the demo page chain completely.
7. Start in demo while offline; all text/navigation/filtering/pagination must work. Missing remote photos should show local illustrations.

## Visual/accessibility

- Inspect small and large iPhones, iPad, and landscape.
- Inspect Light/Dark appearance, maximum Dynamic Type, Increased Contrast, Reduce Transparency, and Reduce Motion.
- Navigate both flows with VoiceOver; check status text, filter labels, image descriptions, and Load more focus.
- Verify native Liquid Glass bars and the video control remain legible over scrolling content.
- Confirm error and empty states do not clip, and date pickers remain usable in a larger sheet.

## Environment note

The editing session's sandbox prevented nested Xcode package/macro sandboxes and access to CoreSimulator IPC. For this session's unsigned compile only, `-IDEPackageSupportDisableManifestSandbox=YES` and `OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'` were passed on the command line. These overrides are not in the project or CI and should not be necessary in a normal Xcode session. No system-wide Xcode settings were changed.
