import ProjectModel
import SwiftUI

/// The course a session in runs was driven on (#552), as a row of the detail's grid: its name,
/// renamed for every session of the course, and a menu to put a wrong match right — the session
/// is on the same course as another the logbook has, or on a course of its own.
struct SessionCourseField: View {
    let entry: LogbookEntry
    let course: CourseTag
    /// The logbook's other courses, those at the session's venue first.
    let otherCourses: [CourseTag]
    let rename: (String) -> Void
    let join: (CourseTag) -> Void
    let separate: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        GridRow {
            Text("Course").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Course", text: $name, prompt: Text("Name this course")).labelsHidden()
                    .focused($focused)
                    .onSubmit(commit)
                    .onAppear { name = course.name }
                    .onChange(of: course) { name = course.name }
                    .onChange(of: focused) { old, new in if old, !new { commit() } }
                    .accessibilityIdentifier("logbook.detail.course")
                    .help("Renames the course for every session driven on it")
                Menu {
                    if !otherCourses.isEmpty {
                        Menu("Same Course as") {
                            ForEach(otherCourses, id: \.id) { other in
                                Button(other.name) { join(other) }
                            }
                        }
                    }
                    Button("New Course", action: separate)
                } label: {
                    Label("Change Course", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .labelStyle(.iconOnly).fixedSize()
                .accessibilityLabel("Change Course")
                .help("Put this session on another course, or on a course of its own")
                .accessibilityIdentifier("logbook.detail.course.change")
            }
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            name = course.name
            return
        }
        if trimmed != course.name { rename(trimmed) }
    }
}
