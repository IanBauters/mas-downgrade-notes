import Foundation

struct ShellResult {
    let status: Int32
    let output: String
}

enum Shell {
    /// Runs a command without blocking the main thread. stdout and stderr are combined.
    static func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            runSync(executable, arguments)
        }.value
    }

    /// Blocking version. Pass your own Process if you need to keep a reference to it.
    static func runSync(_ executable: String, _ arguments: [String], process: Process = Process()) -> ShellResult {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Single-quotes a string for /bin/sh.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command as root. macOS shows its own dialog that asks for an
    /// administrator name and password, so this also works from a standard account.
    static func runAsAdmin(_ command: String, prompt: String) async -> ShellResult {
        let script = "do shell script \"\(appleScriptEscape(command))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
        return await run("/usr/bin/osascript", ["-e", script])
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
