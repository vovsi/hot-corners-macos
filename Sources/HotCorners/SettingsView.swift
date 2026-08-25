import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Hot Corners")
                .font(.title2).bold()
            Text("Pick an app to launch when you move the cursor into a screen corner.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                CornerRow(corner: .topLeft, store: store)
                CornerRow(corner: .topRight, store: store)
                CornerRow(corner: .bottomLeft, store: store)
                CornerRow(corner: .bottomRight, store: store)
            }

            Divider()

            Picker("Card theme", selection: $store.cardTheme) {
                ForEach(CardTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            VStack(spacing: 4) {
                Text("Card size")
                HStack {
                    Slider(value: $store.cardScale, in: 0.5...2.0)
                    Text("\(Int(store.cardScale * 100))%")
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 280)

            Toggle("Launch Hot Corners at login", isOn: $store.launchAtLogin)

            Button("Quit Hot Corners") {
                NSApp.terminate(nil)
            }
            .foregroundStyle(.red)
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct CornerRow: View {
    let corner: Corner
    @ObservedObject var store: SettingsStore

    var body: some View {
        HStack {
            Text(corner.title)
                .frame(width: 100, alignment: .leading)

            if let icon = store.appIcon(for: corner) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(store.appName(for: corner) ?? "")
                    .lineLimit(1)
            } else {
                Text("None")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Choose…") {
                chooseApp()
            }

            if store.appPaths[corner] != nil {
                Button("Clear") {
                    store.setApp(nil, for: corner)
                }
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.setApp(url.path, for: corner)
        }
    }
}
