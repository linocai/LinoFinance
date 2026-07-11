#if os(iOS)
import Foundation
import Photos

// LatestScreenshotFetcher — 快修三 (2026-07-11): auto-fetch path for
// `AIParseScreenshotIntent` (D3 reversed — see `LinoAppIntents.swift`'s doc
// comment on `AIParseScreenshotIntent.screenshot`). Two rounds of "make
// Shortcuts auto-bind 获取最新截屏's output into this intent" (`7ea2fd9` /
// `dd70300`) still failed on a real device — the action never reliably bound
// and running it popped a blocking Files picker. The user's actual ask
// (verbatim): "截图了之后，它能够直接获取最新的截图，然后直接去扫描，直接
// OCR，直接录入" — the APP should grab its own latest screenshot, no
// Shortcuts wiring required. This reads the Photos library directly,
// trading "no photo permission needed" (the original D3) for "actually
// works as a single Back Tap action".
//
// Scope: iOS only (file lives under `Platform/iOS/`, `#if os(iOS)`-gated) —
// macOS is untouched this round; `AIParseScreenshotIntent` still requires an
// explicitly-bound `IntentFile` there.
enum LatestScreenshotFetcher {
    /// A "latest screenshot" older than this is almost certainly not the one
    /// the user just took — reject rather than silently OCR-ing (and
    /// possibly auto-recording, per D1's auto-execute gate) a stale bill
    /// from days ago because of an accidental Back Tap. Named + adjustable,
    /// mirroring `ai.py`'s `IDEMPOTENCY_WINDOW_SECONDS` — a narrow,
    /// documented, tunable safety window rather than a magic number inline.
    static let freshnessWindowSeconds: TimeInterval = 10 * 60

    /// Current Photos authorization status — read by `SettingsIOSView`'s
    /// photo-access card to render 未授权/受限/已授权 without ever
    /// triggering the system prompt as a side effect.
    static func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Triggers the system permission prompt. Only ever called from
    /// `SettingsIOSView`'s explicit "授权照片访问" button — deliberately
    /// NEVER from `fetchLatestScreenshotData` below (a headless Back
    /// Tap/Siri invocation should not conjure a system alert out of
    /// nowhere; `.notDetermined` there is treated the same as "not
    /// authorized yet, go authorize in the app").
    @discardableResult
    static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Fetches the newest Photos-library screenshot's raw image data (no
    /// decode, no resize — `ScreenshotOCR` reads whatever bytes come back).
    /// Throws a `LatestScreenshotFetcherError` whose `.message` is already a
    /// clear, actionable Chinese sentence — callers surface it verbatim.
    static func fetchLatestScreenshotData() async throws -> Data {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            // .notDetermined / .denied / .restricted all collapse to the same
            // "go authorize in the app" message — no inline request here.
            throw LatestScreenshotFetcherError.notAuthorized
        }

        guard let asset = latestScreenshotAsset(), isFresh(asset) else {
            // Under `.limited`, "nothing found" is indistinguishable from
            // "the newest screenshot just isn't in the granted subset" (the
            // system's Limited Library picker doesn't auto-grant new
            // photos) — either way the actionable fix is the same: grant
            // full access. Under full `.authorized`, it really does just
            // mean no recent screenshot.
            throw status == .limited
                ? LatestScreenshotFetcherError.limitedAccessUnavailable
                : LatestScreenshotFetcherError.noRecentScreenshot
        }

        return try await imageData(for: asset)
    }

    private static func isFresh(_ asset: PHAsset) -> Bool {
        guard let creationDate = asset.creationDate else { return false }
        return Date().timeIntervalSince(creationDate) <= freshnessWindowSeconds
    }

    private static func latestScreenshotAsset() -> PHAsset? {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        guard let screenshots = collections.firstObject else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return PHAsset.fetchAssets(in: screenshots, options: options).firstObject
    }

    private static func imageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: LatestScreenshotFetcherError.fetchFailed)
                }
            }
        }
    }
}

enum LatestScreenshotFetcherError: LocalizedError {
    case notAuthorized
    case limitedAccessUnavailable
    case noRecentScreenshot
    case fetchFailed

    /// Already-Chinese, already-actionable — no further translation needed
    /// at the call site.
    var message: String {
        switch self {
        case .notAuthorized:
            "需要照片访问权限才能自动获取最新截图：请打开 LinoFinance → 设置 → 照片访问 授权，或在快捷指令里显式传入截图。"
        case .limitedAccessUnavailable:
            "照片权限是受限模式，取不到新截图；请到系统设置把 LinoFinance 改为允许访问所有照片。"
        case .noRecentScreenshot:
            "最近 10 分钟内没有新截图。先截图再试。"
        case .fetchFailed:
            "截图获取失败，请重试。"
        }
    }

    var errorDescription: String? { message }
}
#endif
