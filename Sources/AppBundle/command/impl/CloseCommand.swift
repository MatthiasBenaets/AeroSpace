import AppKit
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err("Empty workspace"))
        }
        // Access ax directly. Not cool :(
        if await args.quitIfLastWindow.andAsync({ @MainActor @Sendable in (try? await window.macAppUnsafe.getAxWindowsCount(.nonCancellable)) == 1 }) {
            let app = window.macAppUnsafe
            if app.nsApp.terminate() {
                // Capture the parent container for BSP focus tracking
                TilingContainer.__bspClosingParent = window.parent as? TilingContainer
                for workspace in Workspace.all {
                    for w in workspace.allLeafWindowsRecursive where w.app.pid == app.pid {
                        (w as! MacWindow).garbageCollect(skipClosedWindowsCache: true)
                    }
                }
                return .succ
            } else {
                return .fail(io.err("Failed to quit '\(window.app.name ?? "Unknown app")'"))
            }
        } else {
            // Capture the parent container of the window BEFORE closeAxWindow unbinds it.
            // During BSP normalization, we use this to focus the sibling that grows
            // into the freed space (instead of relying on stale MRU order).
            TilingContainer.__bspClosingParent = window.parent as? TilingContainer
            window.closeAxWindow()
            return .succ
        }
    }
}
