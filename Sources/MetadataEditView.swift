import AppKit
import ProjectHubKit
import SwiftUI

struct MetadataEditView: View {
    let projectId: UUID
    @ObservedObject private var store = ProjectStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newIssueURL = ""
    @State private var newPRURL = ""
    @State private var newLinkURL = ""
    @State private var newLinkLabel = ""

    private var project: Project? {
        store.projects.first { $0.id == projectId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Metadata: \(project?.name ?? "Project")")
                .font(.headline)
                .padding(.bottom, 12)

            if !ghAvailable {
                ghHint
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    issuesSection
                    Divider()
                    prsSection
                    Divider()
                    linksSection
                    Divider()
                    openspecSection
                }
            }

            Divider()
                .padding(.top, 8)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - gh availability

    private var ghAvailable: Bool {
        GitHubCLI.resolve() != nil
    }

    private var ghHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text("Install and authenticate the GitHub CLI (`gh`) for PR auto-discovery and issue title fetching.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(6)
        .padding(.bottom, 8)
    }

    // MARK: - Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GitHub Issues")
                .font(.subheadline).bold()

            if let project, !project.githubIssues.isEmpty {
                ForEach(project.githubIssues, id: \.absoluteString) { url in
                    HStack {
                        Text(issueDisplayLabel(url))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeIssue(url)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Issue URL (e.g. https://github.com/org/repo/issues/42)", text: $newIssueURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addIssue() }
                Button("Add") { addIssue() }
                    .disabled(newIssueURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func issueDisplayLabel(_ url: URL) -> String {
        // Extract #N from URL path like /org/repo/issues/42
        let components = url.pathComponents
        if let idx = components.firstIndex(of: "issues"),
           idx + 1 < components.count {
            return "#\(components[idx + 1]) — \(url.absoluteString)"
        }
        return url.absoluteString
    }

    private func addIssue() {
        let trimmed = newIssueURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return }
        guard let project else { return }
        var issues = project.githubIssues
        if !issues.contains(url) {
            issues.append(url)
            store.setGithubIssues(id: projectId, issues: issues)
        }
        newIssueURL = ""
    }

    private func removeIssue(_ url: URL) {
        guard let project else { return }
        var issues = project.githubIssues
        issues.removeAll { $0 == url }
        store.setGithubIssues(id: projectId, issues: issues)
    }

    // MARK: - PRs

    private var prsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pull Requests")
                .font(.subheadline).bold()

            if let project, !project.githubPRs.isEmpty {
                ForEach(project.githubPRs, id: \.url.absoluteString) { entry in
                    HStack {
                        if entry.source == .auto {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .help("Auto-discovered from branch")
                        }
                        Text(prDisplayLabel(entry.url))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if entry.source == .manual {
                            Button {
                                removePR(entry.url)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            HStack {
                TextField("PR URL (e.g. https://github.com/org/repo/pull/51)", text: $newPRURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addPR() }
                Button("Add") { addPR() }
                    .disabled(newPRURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func prDisplayLabel(_ url: URL) -> String {
        let components = url.pathComponents
        if let idx = components.firstIndex(of: "pull"),
           idx + 1 < components.count {
            return "#\(components[idx + 1]) — \(url.absoluteString)"
        }
        return url.absoluteString
    }

    private func addPR() {
        let trimmed = newPRURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return }
        guard let project else { return }
        var prs = project.githubPRs
        if !prs.contains(where: { $0.url == url }) {
            prs.append(GitHubPREntry(url: url, source: .manual))
            store.setGithubPRs(id: projectId, prs: prs)
        }
        newPRURL = ""
    }

    private func removePR(_ url: URL) {
        guard let project else { return }
        var prs = project.githubPRs
        prs.removeAll { $0.url == url }
        store.setGithubPRs(id: projectId, prs: prs)
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Links")
                .font(.subheadline).bold()

            if let project, !project.links.isEmpty {
                ForEach(project.links, id: \.url.absoluteString) { link in
                    HStack {
                        Text("\(link.label) — \(link.url.absoluteString)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeLink(link.url)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Label", text: $newLinkLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 120)
                    .onSubmit { addLink() }
                TextField("URL", text: $newLinkURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addLink() }
                Button("Add") { addLink() }
                    .disabled(
                        newLinkURL.trimmingCharacters(in: .whitespaces).isEmpty
                            || newLinkLabel.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }
        }
    }

    private func addLink() {
        let urlTrimmed = newLinkURL.trimmingCharacters(in: .whitespaces)
        let labelTrimmed = newLinkLabel.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlTrimmed), !urlTrimmed.isEmpty, !labelTrimmed.isEmpty else { return }
        guard let project else { return }
        var links = project.links
        links.append(LabeledLink(url: url, label: labelTrimmed))
        store.setLinks(id: projectId, links: links)
        newLinkURL = ""
        newLinkLabel = ""
    }

    private func removeLink(_ url: URL) {
        guard let project else { return }
        var links = project.links
        links.removeAll { $0.url == url }
        store.setLinks(id: projectId, links: links)
    }

    // MARK: - OpenSpec

    private var openspecSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenSpec Change")
                .font(.subheadline).bold()

            Picker("", selection: Binding(
                get: { project?.openspecChange ?? "" },
                set: { newValue in
                    store.setOpenspecChange(id: projectId, change: newValue.isEmpty ? nil : newValue)
                }
            )) {
                Text("None").tag("")
                ForEach(availableOpenspecChanges(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)
        }
    }

    private func availableOpenspecChanges() -> [String] {
        guard let path = project?.path else { return [] }
        return OpenSpecDetector.listChanges(at: path)
    }
}
