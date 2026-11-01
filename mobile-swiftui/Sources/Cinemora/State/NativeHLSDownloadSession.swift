import AVFoundation
import Foundation

/// AVFoundation HLS package downloader. AVAssetDownloadURLSession requires a
/// background URLSessionConfiguration; passing `.default` raises an Objective-C
/// exception and aborts the app during DownloadManager initialization.
final class NativeHLSDownloadSession: NSObject, AVAssetDownloadDelegate {
    private static var backgroundSessionIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "app.serval4238.taurus3258").cinemora.hls-downloads"
    }

    var onProgress: ((String, Double) -> Void)?
    var onPackage: ((String, URL) -> Void)?
    var onFailure: ((String, Error) -> Void)?

    private var session: AVAssetDownloadURLSession!
    private var observations: [String: NSKeyValueObservation] = [:]
    private var idsByToken: [String: String] = [:]
    private var activeTokenByID: [String: String] = [:]
    private let progressLock = NSLock()
    private let progressDeliveryInterval: TimeInterval = 0.2
    private var pendingProgressByToken: [String: (id: String, fraction: Double)] = [:]
    private var progressWorkByToken: [String: DispatchWorkItem] = [:]
    private var lastProgressDeliveryByToken: [String: TimeInterval] = [:]

    override init() {
        super.init()
        // Apple requires this AVAssetDownloadURLSession to use a background
        // configuration. URLSessionConfiguration.default causes SIGABRT inside
        // AVAssetDownloadURLSession's initializer, which otherwise crashes the
        // app on every launch because DownloadManager is created at app startup.
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }

    func start(id: String, url: URL, title: String) -> Bool {
        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: title, assetArtworkData: nil, options: nil) else { return false }
        let token = UUID().uuidString
        task.taskDescription = token
        idsByToken[token] = id
        activeTokenByID[id] = token
        observations[token] = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            self?.queueProgress(id: id, token: token, fraction: progress.fractionCompleted)
        }
        task.resume()
        return true
    }

    /// Coalesce KVO bursts before they reach SwiftUI/MainActor. Delivery stays
    /// bounded to five updates per second per active download.
    private func queueProgress(id: String, token: String, fraction: Double) {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        progressLock.lock()
        let previous = pendingProgressByToken[token]?.fraction ?? 0
        pendingProgressByToken[token] = (id, max(previous, value))
        guard progressWorkByToken[token] == nil else {
            progressLock.unlock()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let last = lastProgressDeliveryByToken[token] ?? 0
        let delay = max(0, progressDeliveryInterval - max(0, now - last))
        let work = DispatchWorkItem { [weak self] in self?.deliverPendingProgress(token: token) }
        progressWorkByToken[token] = work
        progressLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func deliverPendingProgress(token: String) {
        progressLock.lock()
        let update = pendingProgressByToken.removeValue(forKey: token)
        progressWorkByToken[token] = nil
        lastProgressDeliveryByToken[token] = ProcessInfo.processInfo.systemUptime
        progressLock.unlock()
        guard let update, idsByToken[token] == update.id else { return }
        onProgress?(update.id, update.fraction)
    }

    /// Download task identifiers/destination mappings currently live in memory.
    /// On a new process, cancel any old system task that cannot be re-associated;
    /// otherwise the background session could keep downloading an item the UI
    /// correctly marks as interrupted, wasting storage and network data.
    func cancelUntrackedTasks() {
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                let orphaned = tasks.compactMap { $0 as? AVAssetDownloadTask }.filter { task in
                    guard let token = task.taskDescription else { return true }
                    return self.idsByToken[token] == nil
                }
                orphaned.forEach { $0.cancel() }
            }
        }
    }

    func cancel(id: String) {
        guard let token = activeTokenByID[id] else { return }
        retire(id: id)
        session.getAllTasks { tasks in
            tasks.compactMap { $0 as? AVAssetDownloadTask }
                .filter { $0.taskDescription == token }
                .forEach { $0.cancel() }
        }
    }

    func forget(id: String) { retire(id: id) }

    private func retire(id: String) {
        guard let token = activeTokenByID.removeValue(forKey: id) else { return }
        observations[token] = nil
        idsByToken[token] = nil
        progressLock.lock()
        pendingProgressByToken[token] = nil
        progressWorkByToken.removeValue(forKey: token)?.cancel()
        lastProgressDeliveryByToken[token] = nil
        progressLock.unlock()
    }

    func urlSession(_ session: URLSession,
                    assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let token = assetDownloadTask.taskDescription,
              let id = idsByToken[token] else { return }
        let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        guard expected.isFinite, expected > 0 else { return }
        let loaded = totalTimeRangesLoaded.reduce(0.0) { total, value in
            let seconds = CMTimeGetSeconds(value.timeRangeValue.duration)
            return seconds.isFinite && seconds > 0 ? total + seconds : total
        }
        guard loaded > 0 else { return }
        queueProgress(id: id, token: token, fraction: min(1, loaded / expected))
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let token = assetDownloadTask.taskDescription, let id = idsByToken[token] else { return }
        // Apple explicitly requires apps to persist this location and not move
        // the package. AVFoundation manages the downloaded HLS bundle in place.
        onPackage?(id, location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let token = task.taskDescription, let id = idsByToken[token] else { return }
        observations[token] = nil
        if let error {
            retire(id: id)
            onFailure?(id, error)
        }
    }
}
