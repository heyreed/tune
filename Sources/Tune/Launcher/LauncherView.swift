import SwiftUI
import AppKit

struct LauncherView: View {
    @ObservedObject var viewModel: WindowPickerViewModel
    let onStart: (SessionConfiguration) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tune")
                    .font(.title2).bold()
                Text("Tune your screen for the moment. Everything else disappears.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Pick 1–4 windows to stage. Switch between them with Ctrl+Opt+← / Ctrl+Opt+→ during the session. Hold Esc for 1 second to exit.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text("Windows")
                .font(.headline)
            windowList

            if viewModel.screens.count > 1 {
                Divider()
                Text("Display")
                    .font(.headline)
                Picker("Display", selection: $viewModel.selectedScreenUUID) {
                    ForEach(viewModel.screens, id: \.uuid) { screen in
                        Text(screen.name).tag(Optional(screen.uuid))
                    }
                }
                .labelsHidden()
            }

            Divider()
            Text("Background")
                .font(.headline)
            Picker("Background", selection: $viewModel.selectedBackground) {
                ForEach(BackgroundPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    if let config = viewModel.buildConfiguration() {
                        onStart(config)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedWindowIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { viewModel.refresh() }
    }

    private var windowList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.availableWindows) { window in
                    HStack {
                        Image(systemName: viewModel.selectedWindowIDs.contains(window.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(viewModel.selectedWindowIDs.contains(window.id) ? Color.accentColor : .secondary)
                        Text(window.displayLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggle(window) }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(height: 220)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
