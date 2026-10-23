import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var prefs = Preferences.shared
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()
    @State private var editing: SupportedApp = SupportedApp.frontmost ?? .finder

    private let accessibilityPoll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// The triggers of the app picked at the top.
    private var triggers: Binding<AppTriggers> {
        Binding(get: { prefs.triggers(for: editing) }, set: { prefs.setTriggers($0, for: editing) })
    }

    private var appEnabled: Binding<Bool> {
        editing == .preview ? $prefs.previewEnabled : $prefs.finderEnabled
    }

    var body: some View {
        Form {
            if !trusted {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Tabview needs Accessibility access to read tab bars and see trackpad gestures.")
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }

            Section {
                Picker("App", selection: $editing) {
                    ForEach(SupportedApp.all, id: \.bundleID) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Use Tabview in \(editing.name)", isOn: appEnabled)
            } header: {
                Label("Apps", systemImage: "square.stack")
            } footer: {
                Text("Each app has its own triggers. Preview zooms with a pinch, so you might give it a shortcut instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Group {
                Section {
                    Toggle("Pinch in to show tabs, pinch out to hide", isOn: triggers.pinchEnabled)
                    Picker("While holding", selection: triggers.pinchModifier) {
                        ForEach(ModifierChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(!triggers.wrappedValue.pinchEnabled)
                    LabeledContent("Sensitivity") {
                        HStack {
                            Text("Firm").font(.caption).foregroundStyle(.secondary)
                            Slider(value: triggers.pinchSensitivity, in: 0...1)
                            Text("Light").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!triggers.wrappedValue.pinchEnabled)
                } header: {
                    Label("Trackpad", systemImage: "hand.pinch")
                } footer: {
                    if editing == .preview, triggers.wrappedValue.pinchEnabled, triggers.wrappedValue.pinchModifier == .none {
                        Text("Zooming out of a document in Preview will also open the grid. Pick a key to hold, or turn pinch off.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Keyboard shortcut", isOn: triggers.shortcutEnabled)
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(shortcut: triggers.shortcut)
                    }
                    .disabled(!triggers.wrappedValue.shortcutEnabled)
                } header: {
                    Label("Keyboard", systemImage: "keyboard")
                } footer: {
                    Text("Only active while \(editing.name) is in front, so other apps keep their shortcuts.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Hold a key and scroll", isOn: triggers.scrollEnabled)
                    Picker("Key", selection: triggers.scrollModifier) {
                        ForEach(ModifierChoice.allCases.filter { $0 != .none }) { Text($0.label).tag($0) }
                    }
                    .disabled(!triggers.wrappedValue.scrollEnabled)
                    Toggle("Mouse button", isOn: triggers.mouseButtonEnabled)
                    Picker("Button", selection: triggers.mouseButton) {
                        Text("Middle click").tag(2)
                        Text("Back (button 4)").tag(3)
                        Text("Forward (button 5)").tag(4)
                    }
                    .disabled(!triggers.wrappedValue.mouseButtonEnabled)
                } header: {
                    Label("Mouse", systemImage: "computermouse")
                } footer: {
                    Text("Pointer triggers only fire over a \(editing.name) window, and are swallowed there so the app never sees them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!appEnabled.wrappedValue)

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) {
                        do {
                            if openAtLogin { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } header: {
                Label("General", systemImage: "gearshape")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(accessibilityPoll) { _ in trusted = AXIsProcessTrusted() }
    }
}

/// Click, then press the keys you want.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut…" : shortcut.display)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)

            if shortcut != .showAllTabs {
                Button("Reset") { shortcut = .showAllTabs }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 53, mods.isEmpty { // esc cancels
                stop()
                return nil
            }
            // Require a modifier so a bare letter can't hijack typing in Finder.
            guard !mods.isEmpty else { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
