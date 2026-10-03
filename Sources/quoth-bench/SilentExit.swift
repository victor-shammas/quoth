/// Ends a command with `code` after its message has already been printed.
/// `exiting` maps it to an exit code without printing anything more.
struct SilentExit: Error {
    let code: Int32

    init(_ code: Int32) {
        self.code = code
    }
}
