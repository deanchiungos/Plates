import Foundation

/// Reading the launch arguments the debug flags are spelled with.
///
/// Nearly thirty places in this app take a value off the command line — `-tab map`,
/// `-uncheck NJ`, `-mapZoom 3`, `-asPlayer Mia` — and every one of them had written
/// out the same four tokens by hand: find the flag, check there is something after
/// it, take that. Four tokens is short enough that copying them feels free, which is
/// exactly why it was copied thirty times.
///
/// It stopped being free in `DemoData`. The `-target` option is read twice there,
/// once for the trip and once for the book, and only the book half was written this
/// way. The trip half asked `arguments.contains("past")` — a bare token, matched
/// anywhere in the line, belonging to no flag at all. So one file held two different
/// answers to "how is this option spelled", and `-tab past` (or any argument that
/// happened to equal "past") silently selected a different trip. Nothing about that
/// bug is visible while you are looking at the four tokens; it is only visible when
/// they all live in one place and one caller is not using them.
enum LaunchFlags {

    /// This process's arguments. Taken as a default rather than read inline, so the
    /// same code can be handed a made-up command line by the checks.
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// The value written after `flag`, or nil if the flag is absent or last.
    ///
    /// Deliberately permissive about what a value may look like. An earlier reading
    /// here rejected anything starting with "-", on the reasoning that it is more
    /// likely the next flag than this one's value — true often enough to be tempting,
    /// and wrong for `-rarityDump 40.7,-74.0` the moment somebody drives south of the
    /// equator. The two callers that genuinely want that rule apply it themselves,
    /// where the shape of their value is known.
    static func value(after flag: String, in args: [String] = arguments) -> String? {
        guard let at = args.firstIndex(of: flag), at + 1 < args.count else { return nil }
        return args[at + 1]
    }

    /// Whether a flag that carries no value is present.
    static func isSet(_ flag: String, in args: [String] = arguments) -> Bool {
        args.contains(flag)
    }
}
