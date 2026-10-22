import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var prefs = Preferences.shared
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()

    private let accessibilityPoll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

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
                Toggle("Finder", isOn: $prefs.finderEnabled)
                Toggle("Preview", isOn: $prefs.previewEnabled)
            } header: {
                Label("Apps", systemImage: "square.stack")
            }

            Section {
                Toggle("Pinch in to show tabs, pinch out to hide", isOn: $prefs.pinchEnabled)
                Picker("While holding", selection: $prefs.pinchModifier) {
                    ForEach(ModifierChoice.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!prefs.pinchEnabled)
                LabeledContent("Sensitivity") {
                    HStack {
                        Text("Firm").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $prefs.pinchSensitivity, in: 0...1)
                        Text("Light").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!prefs.pinchEnabled)
            } header: {
                Label("Trackpad", systemImage: "hand.pinch")
            }

            Section {
                Toggle("Keyboard shortcut", isOn: $prefs.shortcutEnabled)
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: $prefs.shortcut)
                }
                .disabled(!prefs.shortcutEnabled)
            } header: {
                Label("Keyboard", systemImage: "keyboard")
            } footer: {
                Text("Only active while Finder or Preview is in front, so other apps keep their shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hold a key and scroll", isOn: $prefs.scrollEnabled)
                Picker("Key", selection: $prefs.scrollModifier) {
                    ForEach(ModifierChoice.allCases.filter { $0 != .none }) { Text($0.label).tag($0) }
                }
                .disabled(!prefs.scrollEnabled)
                Toggle("Mouse button", isOn: $prefs.mouseButtonEnabled)
                Picker("Button", selection: $prefs.mouseButton) {
                    Text("Middle click").tag(2)
                    Text("Back (button 4)").tag(3)
                    Text("Forward (button 5)").tag(4)
                }
                .disabled(!prefs.mouseButtonEnabled)
            } header: {
                Label("Mouse", systemImage: "computermouse")
            } footer: {
                Text("Pointer triggers only fire over a Finder or Preview window, and are swallowed there so the app never sees them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
