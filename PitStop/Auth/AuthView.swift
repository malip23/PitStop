import SwiftUI

/// Sign in / create account with email and password, in PitStop's style.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable { case signIn = "Sign in", signUp = "Create account"; var id: Self { self } }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    var body: some View {
        let auth = app.auth
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Theme.coral.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Theme.coral.opacity(0.4), radius: 16, y: 6)
                    Text("PitStop").font(.largeTitle.weight(.heavy))
                    Text("Run somewhere worth it.").foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if mode == .signUp {
                        field("Your name", text: $name, symbol: "person.fill")
                            .textContentType(.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                    }
                    field("Email", text: $email, symbol: "envelope.fill")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password (6+ characters)", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let error = auth.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let info = auth.infoMessage {
                    Label(info, systemImage: "envelope.badge.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.lime)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    Group {
                        if auth.isWorking { ProgressView().tint(.white) } else { Text(mode.rawValue).font(.headline) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit || auth.isWorking)

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task { await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces)) }
                    }
                    .font(.subheadline)
                    .disabled(email.isEmpty)
                    .frame(minHeight: 44)
                }

                Text("New accounts start as runners. Health data never leaves your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .onChange(of: mode) { _, _ in app.auth.clearMessages() }
        .animation(.snappy, value: mode)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func submit() {
        guard canSubmit else { return }
        let email = email.trimmingCharacters(in: .whitespaces)
        Task {
            if mode == .signUp {
                await app.auth.signUp(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
            } else {
                await app.auth.signIn(email: email, password: password)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            TextField(title, text: text)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
