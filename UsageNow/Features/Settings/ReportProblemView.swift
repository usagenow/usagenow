import AppKit
import SwiftUI

/// Shows the whole diagnostic report and lets the person send it — on
/// GitHub or by email — or copy it. Nothing is sent from here: both open
/// the person's own browser or mail app with the text filled in.
struct ReportProblemView: View {
    static let issuesURL = URL(string: "https://github.com/usagenow/usagenow/issues/new")!
    static let supportEmail = "hi@usagenow.com"
    /// Keeps a prefilled link well under what browsers and GitHub accept.
    private static let maxReportLength = 6_000

    let report: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a Problem")
                .font(.headline)
            Text("This is everything the report contains: versions, screens, settings, and what each provider shows. No names, emails, file paths, keys, or prompts. Nothing is sent until you send it yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(verbatim: report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 240)
            .background(Palette.badgeFill, in: .rect(cornerRadius: 8))

            HStack {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Email…") { open(emailURL) }
                Button("Open GitHub Issue…") { open(issueURL) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }

    private var body_: String {
        let trimmed = report.count > Self.maxReportLength ? String(report.prefix(Self.maxReportLength)) + "\n…" : report
        return """
            **What happened?**

            Describe what you saw and what you expected. A screenshot or screen recording helps.

            **Diagnostics** (Settings › About › Report a Problem)
            ```
            \(trimmed)
            ```
            """
    }

    private var issueURL: URL? {
        var components = URLComponents(url: Self.issuesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Problem: "),
            URLQueryItem(name: "body", value: body_),
        ]
        return components?.url
    }

    private var emailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "UsageNow \(AppInfo.version) problem report"),
            URLQueryItem(name: "body", value: body_),
        ]
        return components.url
    }
}
