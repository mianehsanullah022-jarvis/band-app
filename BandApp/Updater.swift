import Foundation
import SwiftUI
import UIKit

/// Checks GitHub for a newer version of Band and opens SideStore to install it.
@MainActor
final class Updater: ObservableObject {
    static let sourceURL = "https://raw.githubusercontent.com/mianehsanullah022-jarvis/band-app/altsource/source.json"
    static let releasesURL = "https://github.com/mianehsanullah022-jarvis/band-app/releases/latest"

    @Published var latestVersion: String?
    @Published var updateAvailable = false
    @Published var checking = false
    @Published var lastError: String?
    @Published var dismissedBuild: Int = UserDefaults.standard.integer(forKey: "dismissedBuild")

    private var latestBuild = 0

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    /// Show the banner only for a version the user hasn't closed already.
    var showBanner: Bool { updateAvailable && latestBuild != dismissedBuild }

    func check() async {
        checking = true
        lastError = nil
        defer { checking = false }
        guard let url = URL(string: Self.sourceURL + "?t=\(Int(Date().timeIntervalSince1970))") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apps = json["apps"] as? [[String: Any]],
                  let versions = apps.first?["versions"] as? [[String: Any]],
                  let newest = versions.first,
                  let build = Int(newest["buildVersion"] as? String ?? "") else {
                lastError = "Couldn't read the update info."
                return
            }
            latestBuild = build
            latestVersion = newest["version"] as? String
            withAnimation(Theme.spring) { updateAvailable = build > currentBuild }
        } catch {
            lastError = "No internet, or GitHub didn't answer."
        }
    }

    func dismiss() {
        UserDefaults.standard.set(latestBuild, forKey: "dismissedBuild")
        withAnimation(Theme.spring) { dismissedBuild = latestBuild }
    }

    /// Opens SideStore so the user can tap Update. Falls back to the download page.
    func openSideStore() {
        guard let url = URL(string: "sidestore://") else { return }
        UIApplication.shared.open(url) { ok in
            if !ok, let page = URL(string: Self.releasesURL) {
                UIApplication.shared.open(page)
            }
        }
    }

    /// Adds the Band source to SideStore. If that doesn't open, copies the link instead.
    func addSourceToSideStore(copied: @escaping () -> Void) {
        let encoded = Self.sourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.sourceURL
        guard let url = URL(string: "sidestore://source?url=\(encoded)") else { return }
        UIApplication.shared.open(url) { ok in
            if !ok {
                UIPasteboard.general.string = Self.sourceURL
                copied()
            }
        }
    }
}

/// Banner shown on Home when a new version is ready.
struct UpdateBanner: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "arrow.down.circle.fill", color: Theme.green, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Text("Version \(updater.latestVersion ?? "") is ready").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                updater.openSideStore()
            } label: {
                Text("Update")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.green)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressStyle())
            Button { updater.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Hide update message")
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.green.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// "Updates" screen in More.
struct UpdatesView: View {
    @EnvironmentObject var updater: Updater
    @State private var copied = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    IconBadge(symbol: "app.badge.fill", color: Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This version").foregroundColor(Theme.text)
                        Text("\(updater.currentVersion)").font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    if updater.checking { ProgressView() }
                    else if updater.updateAvailable {
                        Text("New: \(updater.latestVersion ?? "")").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                    } else if updater.latestVersion != nil {
                        Text("Up to date").font(.system(size: 13)).foregroundColor(Theme.green)
                    }
                }
                .listRowBackground(Theme.card)

                Button { Task { await updater.check() } } label: {
                    Label("Check for updates", systemImage: "arrow.clockwise")
                }
                .listRowBackground(Theme.card)

                if updater.updateAvailable {
                    Button { updater.openSideStore() } label: {
                        Label("Open SideStore to update", systemImage: "arrow.down.circle.fill")
                    }
                    .listRowBackground(Theme.card)
                }

                if let e = updater.lastError {
                    Text(e).font(.system(size: 12)).foregroundColor(Theme.amber).listRowBackground(Theme.card)
                }
            } header: { Text("Updates") }

            Section {
                Button {
                    updater.addSourceToSideStore { copied = true }
                } label: {
                    Label("Add Band to SideStore", systemImage: "plus.app.fill")
                }
                .listRowBackground(Theme.card)
                if copied {
                    Text("Link copied. In SideStore go to Sources → + and paste it.")
                        .font(.system(size: 12)).foregroundColor(Theme.green).listRowBackground(Theme.card)
                }
                Text(Updater.sourceURL)
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.muted)
                    .textSelection(.enabled)
                    .listRowBackground(Theme.card)
            } header: { Text("One-time setup") } footer: {
                Text("Do this once after installing SideStore. After that, new versions show up in SideStore with an Update button.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .task { await updater.check() }
    }
}
