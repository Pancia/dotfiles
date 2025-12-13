#!/usr/bin/swift

import Foundation

// MARK: - Logging

func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(timestamp)] \(message)")
    fflush(stdout)
}

// MARK: - Process Management

func isKittyRunning() -> Bool {
    let task = Process()
    let pipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "kitty"]
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let isRunning = task.terminationStatus == 0 && !output.isEmpty
        log("Kitty: Process \(isRunning ? "found" : "not found")")
        return isRunning
    } catch {
        log("Kitty: Check failed - \(error.localizedDescription)")
        return false
    }
}

// MARK: - VPC Management

func openSanctuaryVPC() {
    log("VPC: Opening sanctuary.vpc")

    let vpcPath = "/Users/anthony/dotfiles/vpc/sanctuary.vpc"
    let task = Process()
    let pipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [vpcPath]
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
            log("VPC: Successfully opened sanctuary.vpc")
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            log("VPC: Failed to open - \(output)")
        }
    } catch {
        log("VPC: Error opening file - \(error.localizedDescription)")
    }
}

func checkKittyAndOpenVPC() {
    if !isKittyRunning() {
        log("VPC: No Kitty process found, opening sanctuary.vpc")
        openSanctuaryVPC()
    } else {
        log("VPC: Kitty is running, skipping VPC open")
    }
}

// MARK: - Health Check Loop

func startHealthCheck() {
    log("HealthCheck: Starting 30-second health check loop")

    Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
        log("HealthCheck: Checking Kitty status...")
        checkKittyAndOpenVPC()
    }
}

// MARK: - Main

log("========================================")
log("Sanctuary Service")
log("========================================")
log("Features:")
log("  - Screen Unlock Listener")
log("  - Health Check Loop (30s)")
log("  - Kitty Detection & VPC Opener")
log("========================================")

// Start health check loop
startHealthCheck()

// Listen for screen unlock notifications
let center = DistributedNotificationCenter.default()
center.addObserver(
    forName: NSNotification.Name("com.apple.screenIsUnlocked"),
    object: nil,
    queue: nil
) { notification in
    log("UnlockEvent: Screen unlocked, checking Kitty")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        checkKittyAndOpenVPC()
    }
}

log("✓ Service initialized successfully")
log("⏳ Monitoring screen unlocks...")
log("")

// Keep the run loop alive
RunLoop.main.run()
