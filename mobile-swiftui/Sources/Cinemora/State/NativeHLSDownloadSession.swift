import AVFoundation
import Foundation

/// Foreground AVFoundation HLS package downloader. Tasks are intentionally not
/// restored after process relaunch; incomplete native tasks are marked failed.
final class NativeHLSDownloadSession: NSObject, AVAssetDownloadDelegate {
    var onProgress: ((String, Double) -> Void)?
    var onPackage: ((String, URL) -> Void)?
    var onFailure: ((String, Error) -> Void)?

    private var session: AVAssetDownloadURLSession!
    private var observations: [String: NSKeyValueObservation] = [:]
    private var destinations: [String: URL] = [:]

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }

    func start(id: String, url: URL, title: String, destination: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: title, assetArtworkData: nil, options: nil) else { return false }
        task.taskDescription = id
        destinations[id] = destination
        observations[id] = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            self?.onProgress?(id, progress.fractionCompleted)
        }
        task.resume()
        return true
    }

    func cancel(id: String) {
        observations[id] = nil
        destinations[id] = nil
        session.getAllTasks { tasks in
            tasks.compactMap { $0 as? AVAssetDownloadTask }
                .filter { $0.taskDescription == id }
                .forEach { $0.cancel() }
        }
    }

    func forget(id: String) {
        observations[id] = nil
        destinations[id] = nil
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        guard let destination = destinations[id] else {
            onFailure?(id, NSError(domain: "Cinemora.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không có đường dẫn lưu package."]))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            onPackage?(id, destination)
        } catch {
            destinations[id] = nil
            onFailure?(id, error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        observations[id] = nil
        if error != nil { destinations[id] = nil }
        if let error { onFailure?(id, error) }
    }
}
