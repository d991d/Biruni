import Foundation

/// Thin wrapper around Process for running command-line tools and
/// capturing their output. Used by ArchiveService (unzip/tar), the
/// NC command line, and the user-defined F2 menu.
public enum ShellRunner {

    public struct Result {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Runs `/usr/bin/env <executable> <arguments>` synchronously, in `directory` if given.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], directory: String? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: "Failed to launch \(executable): \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Runs a raw shell command line (as typed at NC's command line) through
    /// the user's own login shell, in `directory`.
    ///
    /// Earlier this ran `/bin/sh -c commandLine` directly, which uses a bare
    /// minimal PATH (roughly `/usr/bin:/bin:/usr/sbin:/sbin`) with no
    /// profile/rc files sourced - so anything installed via Homebrew, a
    /// version manager (rbenv/nvm/pyenv), or defined as a shell function or
    /// alias would silently fail with "command not found" even though the
    /// exact same text works fine typed into Terminal.app. Launching the
    /// user's actual `$SHELL` as a login shell (`-l`) sources the same
    /// profile files an interactive terminal would, so PATH and everything
    /// else built on it matches what "running a terminal command" here
    /// actually means to the person typing it.
    public static func runShellLine(_ commandLine: String, directory: String) -> Result {
        let process = Process()
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-c", commandLine]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: "Failed to launch shell: \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
