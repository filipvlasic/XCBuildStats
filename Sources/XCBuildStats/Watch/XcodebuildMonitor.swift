import Foundation
import Darwin

/// Watches the user's `xcodebuild` processes and reports each build run when it
/// exits. Command-line builds — AI agents working in their own worktrees,
/// scripts, Terminal — usually leave nothing in DerivedData's log store (Xcode
/// writes it only for `test` or with `-resultBundlePath`, and agents often build
/// into a throwaway DerivedData), so the process is the only reliable record.
/// Like the DerivedData watch, it only sees runs while the app is running.
final class XcodebuildMonitor {
    static let processName: String = "xcodebuild"

    private let accepts: (String) -> Bool
    private let onFinish: (XcodebuildRun) -> Void
    private let lock: NSLock = NSLock()
    private var generation: Int = 0
    private var isRunning: Bool = false

    /// `accepts` decides by executable path which processes named xcodebuild count.
    init(accepts: @escaping (String) -> Bool = XcodebuildMonitor.isXcodeToolchain, onFinish: @escaping (XcodebuildRun) -> Void) {
        self.accepts = accepts
        self.onFinish = onFinish
    }

    /// The real tool inside an Xcode bundle, or the `/usr/bin` shim that execs
    /// it — not some other binary that happens to be called xcodebuild.
    static func isXcodeToolchain(_ executable: String) -> Bool {
        return executable == "/usr/bin/xcodebuild" || executable.hasSuffix(".app/Contents/Developer/usr/bin/xcodebuild")
    }

    func start() {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !isRunning else {
            return
        }
        isRunning = true
        generation += 1
        let current: Int = generation
        let thread: Thread = Thread { [self] in
            run(generation: current)
        }
        thread.name = "com.filipvlasic.xcbuildstats.xcodebuild-monitor"
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        lock.lock()
        isRunning = false
        generation += 1
        lock.unlock()
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return generation == self.generation
    }

    private struct Tracked {
        let invocation: XcodebuildInvocation
        let started: Date
    }

    /// Polls the process table once a second for new xcodebuild runs; exits arrive
    /// through kqueue with their exact time and exit status.
    private func run(generation: Int) {
        let queue: Int32 = kqueue()
        guard queue >= 0 else {
            return
        }
        defer {
            close(queue)
        }
        var tracked: [pid_t: Tracked] = [:]
        // Non-build runs (`-showBuildSettings`, `-list`…) are remembered by pid and
        // start time so their arguments are read only once.
        var ignored: [pid_t: Date] = [:]
        var events: [kevent] = Array(repeating: kevent(), count: 16)
        var timeout: timespec = timespec(tv_sec: 1, tv_nsec: 0)
        while isCurrent(generation) {
            discover(queue: queue, tracked: &tracked, ignored: &ignored)
            let count: Int32 = kevent(queue, nil, 0, &events, Int32(events.count), &timeout)
            let stopped: Date = Date()
            for event in events.prefix(Int(max(count, 0))) where event.filter == Int16(EVFILT_PROC) {
                guard let run: Tracked = tracked.removeValue(forKey: pid_t(event.ident)) else {
                    continue
                }
                let hasStatus: Bool = event.fflags & UInt32(NOTE_EXITSTATUS) != 0
                onFinish(XcodebuildRun(
                    pid: pid_t(event.ident),
                    invocation: run.invocation,
                    started: run.started,
                    stopped: stopped,
                    exit: hasStatus ? ProcessExit(waitStatus: Int32(truncatingIfNeeded: event.data)) : .exited(0)
                ))
            }
        }
    }

    private func discover(queue: Int32, tracked: inout [pid_t: Tracked], ignored: inout [pid_t: Date]) {
        let processes: [(pid: pid_t, started: Date)] = Self.userProcesses(named: Self.processName)
        let alive: Set<pid_t> = Set(processes.map { $0.pid })
        ignored = ignored.filter { alive.contains($0.key) }
        for process in processes where tracked[process.pid] == nil && ignored[process.pid] != process.started {
            guard let (executable, argv) = Self.arguments(of: process.pid), accepts(executable) else {
                ignored[process.pid] = process.started
                continue
            }
            let invocation: XcodebuildInvocation = XcodebuildInvocation(
                arguments: Array(argv.dropFirst()),
                workingDirectory: Self.workingDirectory(of: process.pid)
            )
            guard invocation.isBuild else {
                ignored[process.pid] = process.started
                continue
            }
            var change: kevent = kevent(
                ident: UInt(process.pid),
                filter: Int16(EVFILT_PROC),
                flags: UInt16(EV_ADD | EV_ONESHOT),
                fflags: NOTE_EXIT | UInt32(NOTE_EXITSTATUS),
                data: 0,
                udata: nil
            )
            // Fails only when the process already exited — a sub-second run.
            guard kevent(queue, &change, 1, nil, 0, nil) == 0 else {
                continue
            }
            tracked[process.pid] = Tracked(invocation: invocation, started: process.started)
        }
    }

    static func userProcesses(named name: String) -> [(pid: pid_t, started: Date)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            return []
        }
        let stride: Int = MemoryLayout<kinfo_proc>.stride
        // Headroom: the table can grow between the two calls.
        var infos: [kinfo_proc] = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = infos.count * stride
        guard sysctl(&mib, UInt32(mib.count), &infos, &size, nil, 0) == 0 else {
            return []
        }
        var result: [(pid: pid_t, started: Date)] = []
        for var info in infos.prefix(size / stride) {
            let command: String = withUnsafeBytes(of: &info.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard command == name else {
                continue
            }
            let start: timeval = info.kp_proc.p_un.__p_starttime
            let started: Date = Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
            result.append((info.kp_proc.p_pid, started))
        }
        return result
    }

    static func arguments(of pid: pid_t) -> (executable: String, argv: [String])? {
        var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var argMaxSize: Int = MemoryLayout<Int32>.size
        guard sysctl(&argMaxMib, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else {
            return nil
        }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer: [UInt8] = [UInt8](repeating: 0, count: Int(argMax))
        var size: Int = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return parseProcessArguments(Array(buffer.prefix(size)))
    }

    /// `KERN_PROCARGS2` layout: argc as Int32, the executable path, NUL padding,
    /// then argc NUL-terminated argv strings (followed by the environment).
    static func parseProcessArguments(_ bytes: [UInt8]) -> (executable: String, argv: [String])? {
        guard bytes.count > MemoryLayout<Int32>.size else {
            return nil
        }
        let argc: Int = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index: Int = MemoryLayout<Int32>.size
        let executableStart: Int = index
        while index < bytes.count, bytes[index] != 0 {
            index += 1
        }
        let executable: String = String(decoding: bytes[executableStart..<index], as: UTF8.self)
        while index < bytes.count, bytes[index] == 0 {
            index += 1
        }
        var argv: [String] = []
        while argv.count < argc, index < bytes.count {
            var end: Int = index
            while end < bytes.count, bytes[end] != 0 {
                end += 1
            }
            argv.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return argv.count == argc ? (executable, argv) : nil
    }

    static func workingDirectory(of pid: pid_t) -> String? {
        var info: proc_vnodepathinfo = proc_vnodepathinfo()
        let size: Int32 = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        let path: String = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
