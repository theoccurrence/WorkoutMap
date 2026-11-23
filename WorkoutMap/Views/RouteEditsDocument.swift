import SwiftUI
import UniformTypeIdentifiers

/// The file the route edits are exported to and imported from — a plain JSON document, readable on
/// any device and by any tool, so the edits can travel to another phone with the same workouts in
/// iCloud. It carries the store's own data untouched (`RouteEditStore.Document`); this type is only
/// the wrapper SwiftUI's `fileExporter` and `fileImporter` work with.
struct RouteEditsDocument: FileDocument {
    /// A `.json` file, so the share sheet and the file picker know what to do with it.
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
