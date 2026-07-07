import Foundation
import CoreServices

final class DerivedDataWatcher {
    private let path: String
    private let onChange: () -> Void
    private let queue: DispatchQueue = DispatchQueue(label: "com.filipvlasic.xcbuildstats.fsevents")
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        var context: FSEventStreamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            let watcher: DerivedDataWatcher = Unmanaged<DerivedDataWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleChange()
        }
        let flags: UInt32 = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream: FSEventStreamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
