import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("SecureChat")
                    .font(.title)
                    .fontWeight(.bold)

                Text("End-to-End Verschlüsselt")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 40)

            VStack(spacing: 12) {
                TextField("Benutzername", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    if showPassword {
                        TextField("Passwort", text: $password)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Passwort", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                }
            }

            Button(action: login) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Anmelden")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(username.isEmpty || password.isEmpty || isLoading)

            HStack {
                Text("Noch kein Konto?")
                    .foregroundColor(.gray)
                Button("Jetzt registrieren") {
                    // TODO: Registration flow
                }
                .foregroundColor(.blue)
            }
            .font(.caption)

            Spacer()

            VStack(spacing: 8) {
                Divider()
                Text("Sicher verschlüsselt mit AES-256")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private func login() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            authManager.login(username: username, password: password)
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager())
}
