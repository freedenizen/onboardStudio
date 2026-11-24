import Foundation
import Importers

/// Whether a file chosen as a project's data is one the app can read, asked before it is added.
public enum DataFileCheck {
    /// Why `url` is not added as a data input, in the user's words; `nil` when an importer knows
    /// it. The editor used to add any file: one that no importer knew sat in the project under a
    /// warning triangle with its attributes "Reading…" for good, where the Logbook refuses the
    /// same file and adds nothing (#668).
    public static func refusal(of url: URL) -> String? {
        let name = url.lastPathComponent
        do {
            guard try FormatDetector.detect(url) == nil else { return nil }
            return "“\(name)” was not added: it is not a data file this app reads. "
                + "Help ▸ Supported Data Formats lists the ones it does."
        } catch {
            return "“\(name)” was not added: it could not be read (\(error.localizedDescription))."
        }
    }
}
