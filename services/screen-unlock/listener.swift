#!/usr/bin/swift

import Foundation
import Cocoa

func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(timestamp)] \(message)")
    fflush(stdout)
}

// MARK: - App Process Management

func isAppRunning(appName: String) -> Bool {
    let apps = NSWorkspace.shared.runningApplications
    let runningAppNames = apps.compactMap { $0.localizedName }
    log("Checking for running app: \(appName), found \(runningAppNames.count) running apps")

    let found = apps.contains { app in
        guard let name = app.localizedName else { return false }
        return name == appName || name.contains(appName)
    }

    if found {
        log("Found running app matching: \(appName)")
    } else {
        log("No running app found matching: \(appName)")
    }

    return found
}

func killApp(appName: String) {
    log("Attempting to kill app: \(appName)")
    let apps = NSWorkspace.shared.runningApplications
    var killed = 0

    for app in apps {
        if let name = app.localizedName, name.contains(appName) {
            log("Terminating app: \(name) (PID: \(app.processIdentifier))")
            app.terminate()
            killed += 1
        }
    }

    if killed > 0 {
        log("Terminated \(killed) app(s)")
    } else {
        log("No apps found to terminate")
    }
}

// MARK: - HTTP Requests

func checkSanctuaryStatus(completion: @escaping (Bool, [String: Any]?) -> Void) {
    guard let url = URL(string: "http://127.0.0.1:6447/status") else {
        log("Error: Invalid status URL")
        completion(false, nil)
        return
    }

    log("HTTP GET \(url.absoluteString)")
    let startTime = Date()

    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        let elapsed = Date().timeIntervalSince(startTime)

        if let error = error {
            log("HTTP GET failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            completion(false, nil)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log("HTTP GET failed: Invalid response type")
            completion(false, nil)
            return
        }

        log("HTTP GET completed in \(String(format: "%.2f", elapsed))s: status \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200,
              let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("HTTP GET failed: status=\(httpResponse.statusCode), data=\(data?.count ?? 0) bytes")
            completion(false, nil)
            return
        }

        log("Backend status OK, data: \(json)")
        completion(true, json)
    }
    task.resume()
}

func showSanctuaryWindow(completion: @escaping (Bool, [String: Any]?) -> Void) {
    guard let url = URL(string: "http://127.0.0.1:6447/show-window") else {
        log("Error: Invalid show-window URL")
        completion(false, nil)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    log("HTTP POST \(url.absoluteString)")
    let startTime = Date()

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        let elapsed = Date().timeIntervalSince(startTime)

        if let error = error {
            log("HTTP POST failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            completion(false, nil)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log("HTTP POST failed: Invalid response type")
            completion(false, nil)
            return
        }

        log("HTTP POST completed in \(String(format: "%.2f", elapsed))s: status \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200,
              let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("HTTP POST failed: status=\(httpResponse.statusCode), data=\(data?.count ?? 0) bytes")
            completion(false, nil)
            return
        }

        if let action = json["action"] as? String {
            let message = action == "focused_existing" ? "Focused existing window" : "Created new window"
            log("Sanctuary: \(message), response: \(json)")
        }
        completion(true, json)
    }
    task.resume()
}

// MARK: - Process Launch

func launchSanctuaryProcess() {
    log("Launching Sanctuary process...")

    let script = """
    export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
    cd /Users/anthony/projects/sanctuary
    npm start
    """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = ["-c", script]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.terminationHandler = { process in
        let exitCode = process.terminationStatus
        if exitCode == 0 {
            log("Sanctuary: Process exited successfully (code: \(exitCode))")
        } else {
            log("Sanctuary: Process exited with error (code: \(exitCode))")
        }

        // Try to read any output
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            log("Sanctuary process output: \(output.prefix(500))")
        }
    }

    do {
        try task.run()
        log("Sanctuary: Process started (PID: \(task.processIdentifier))")
    } catch {
        log("Sanctuary: Failed to start process: \(error.localizedDescription)")
    }
}

// MARK: - Main Launch Logic

func launchSanctuary() {
    log("========================================")
    log("Screen unlock event detected!")
    log("========================================")
    log("Sanctuary: Checking backend status...")

    // First try to communicate with the backend
    checkSanctuaryStatus { success, data in
        if success {
            log("Sanctuary: ✓ Backend is healthy")
            log("Sanctuary: Requesting window show/focus...")
            showSanctuaryWindow { windowSuccess, windowData in
                if windowSuccess {
                    log("Sanctuary: ✓ Window operation completed successfully")
                } else {
                    log("Sanctuary: ✗ Failed to show window via backend")
                }
            }
        } else {
            log("Sanctuary: ✗ Backend not responding")
            log("Sanctuary: Checking for running Electron process...")

            // Backend not responding, check if process is running but backend failed
            if isAppRunning(appName: "Electron") {
                log("Sanctuary: ⚠ Process detected but backend unresponsive")
                log("Sanctuary: Decision: Kill and restart process")
                killApp(appName: "Electron")

                log("Sanctuary: Waiting 2 seconds before restart...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    log("Sanctuary: Initiating restart after delay")
                    launchSanctuaryProcess()
                }
            } else {
                log("Sanctuary: No Electron process detected")
                log("Sanctuary: Decision: Launch fresh Sanctuary process")
                launchSanctuaryProcess()
            }
        }
    }
}

// MARK: - Main

log("========================================")
log("Sanctuary Screen Unlock Listener v1.0")
log("========================================")
log("Configuration:")
log("  - Backend URL: http://127.0.0.1:6447")
log("  - Sanctuary Path: /Users/anthony/projects/sanctuary")
log("  - Unlock Delay: 1 second")
log("========================================")

// Listen for screen unlock notifications
let center = DistributedNotificationCenter.default()
center.addObserver(
    forName: NSNotification.Name("com.apple.screenIsUnlocked"),
    object: nil,
    queue: nil
) { notification in
    log("Received screen unlock notification")
    // Add a small delay to ensure the desktop is ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        launchSanctuary()
    }
}

log("✓ Listener initialized successfully")
log("⏳ Waiting for screen unlock events...")
log("")

// Keep the run loop alive
RunLoop.main.run()
