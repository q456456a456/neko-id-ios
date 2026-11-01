import SwiftUI
import UIKit

// Local integration host, copied over the entry point only in a temporary test
// workspace. Uses the actual system background session; never production APIs.
@main
struct GenerationBackgroundTestApp: App {
    @UIApplicationDelegateAdaptor(NekoAppDelegate.self) private var appDelegate
    @State private var status = "Waiting"
    @State private var started = false

    var body: some Scene {
        WindowGroup {
            Text(status).task {
                guard !started else { return }
                started = true
                await run()
            }
        }
    }

    @MainActor
    private func run() async {
        let endpoint = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--endpoint=") }!
            .replacingOccurrences(of: "--endpoint=", with: "")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("result.txt"))
        func record(_ name: String, _ data: Data) { try? data.write(to: documents.appendingPathComponent(name), options: .atomic) }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"fixture\":\"background-generation\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        status = "Request in progress"
        record("started.txt", Data(status.utf8))
        do {
            let (data, response) = try await NekoGenerationTransport.shared.data(for: request, trace: NekoPerformanceTrace("background_integration"))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  String(decoding: data, as: UTF8.self) == "{\"result\":\"completed-once\"}" else { throw URLError(.badServerResponse) }
            status = "PASS: original response received"
            record("result.txt", Data(status.utf8))
        } catch {
            status = "FAIL: \(error)"
            record("result.txt", Data(status.utf8))
        }
    }
}
