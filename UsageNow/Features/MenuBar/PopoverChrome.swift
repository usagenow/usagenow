import AppKit
import SwiftUI

/// Brand on the left, refresh and settings on the right.
struct PopoverHeaderView: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            BrandLogo()
                .frame(height: 15)
                .foregroundStyle(.primary)
            Spacer()
            RefreshButton(isRefreshing: isRefreshing, action: onRefresh)
                .keyboardShortcut("r")
            IconButton(title: "Settings…", systemImage: "gearshape", action: onOpenSettings)
                .keyboardShortcut(",")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }
}

/// Last-updated status and Quit.
struct PopoverFooterView: View {
    let lastRefreshAt: Date?
    let hasFailures: Bool
    let now: Date

    private let formatter = ResetTimeFormatter()

    var body: some View {
        HStack(spacing: 6) {
            if let lastRefreshAt {
                Circle()
                    .fill(hasFailures ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(formatter.updatedDescription(lastRefreshAt, now: now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextButton(title: "Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .accessibilityLabel(Text("Quit UsageNow"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }
}

struct LoadingStateView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Checking usage…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}

/// Every supported provider is turned off in Settings.
struct NoProvidersEnabledView: View {
    let onOpenProviderSettings: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("No providers enabled")
                .font(.headline)
            Text("Choose a provider in Settings to start tracking usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Provider Settings", action: onOpenProviderSettings)
                .controlSize(.small)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 36)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("No providers detected")
                .font(.headline)
            Text("Install or use Codex, Claude Code, Gemini CLI, or Antigravity to start tracking usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 36)
        .accessibilityElement(children: .combine)
    }
}
