import Foundation

struct SubmissionJournal {
    private let url: URL
    init(directory: URL = URL.applicationSupportDirectory) {
        url = directory.appending(path: "HermesPocket", directoryHint: .isDirectory).appending(path: "pending-submissions.json")
    }

    func read() throws -> [PendingSubmission] {
        guard FileManager.default.fileExists(atPath: url.path()) else { return [] }
        return try JSONDecoder().decode([PendingSubmission].self, from: Data(contentsOf: url))
    }

    func save(_ submissions: [PendingSubmission]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(submissions)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
