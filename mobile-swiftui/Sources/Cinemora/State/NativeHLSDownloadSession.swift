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
    private var destinationsByToken: [String: URL] = [:]
    private var activeTokenByID: [String: String] = [:]

    override init() {
        super.init()
        // Apple requires this AVAssetDownloadURLSession to use a background
        // configuration. URLSessionConfiguration.default causes SIGABRT inside
        // AVAssetDownloadURLSession's initializer, which otherwise crashes the
        // app on every launch because DownloadManager is created at app startup.
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = false
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }

    func start(id: String, url: URL, title: String, destination: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: title, assetArtworkData: nil, options: nil) else { return false }
        let token = UUID().uuidString
        task.taskDescription = token
        idsByToken[token] = id
        destinationsByToken[token] = destination
        activeTokenByID[id] = token
        observations[token] = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            guard let self, self.idsByToken[token] == id else { return }
            self.onProgress?(id, progress.fractionCompleted)
        }
        task.resume()
        return true
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
        destinationsByToken[token] = nil
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let token = assetDownloadTask.taskDescription, let id = idsByToken[token] else { return }
        guard let destination = destinationsByToken[token] else {
            onFailure?(id, NSError(domain: "Cinemora.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không có đường dẫn lưu package."]))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            onPackage?(id, destination)
        } catch {
            retire(id: id)
            onFailure?(id, error)
        }
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
