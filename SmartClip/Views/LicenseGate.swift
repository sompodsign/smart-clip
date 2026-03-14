import SwiftUI

struct LicenseGate: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @State private var showActivation = false
    @State private var licenseKey = ""
    @State private var error = ""
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: viewModel.isPro ? "circle.fill" : "circle")
                    .font(.system(size: 6)).foregroundStyle(.tertiary)
                Text(viewModel.license.message)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }

            if viewModel.isPro {
                HStack(spacing: 4) {
                    Button("Manage") {
                        if let url = URL(string: viewModel.customerPortalUrl) { NSWorkspace.shared.open(url) }
                    }.buttonStyle(LicenseButtonStyle())
                    Button("Revalidate") {
                        Task { isLoading = true; _ = await viewModel.revalidateLicense(); isLoading = false }
                    }.buttonStyle(LicenseButtonStyle()).disabled(isLoading)
                    Button("Deactivate") {
                        Task { try? await viewModel.deactivateLicense() }
                    }.buttonStyle(LicenseButtonStyle(isDanger: true))
                }
            } else if showActivation {
                VStack(spacing: 6) {
                    TextField("Enter license key...", text: $licenseKey)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                        .onSubmit { activate() }
                    if !error.isEmpty {
                        Text(error).font(.system(size: 10)).foregroundStyle(.red)
                    }
                    HStack(spacing: 4) {
                        Button(isLoading ? "Activating..." : "Activate") { activate() }
                            .buttonStyle(LicenseButtonStyle(isPrimary: true)).disabled(isLoading)
                        Button("Cancel") { showActivation = false; error = "" }
                            .buttonStyle(LicenseButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Button("Monthly") {
                        if let urlStr = viewModel.checkoutUrl(cycle: "monthly"), let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                    }.buttonStyle(LicenseButtonStyle(isPrimary: true))
                    Button("Yearly (Best value)") {
                        if let urlStr = viewModel.checkoutUrl(cycle: "yearly"), let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                    }.buttonStyle(LicenseButtonStyle(isPrimary: true))
                    Button("Activate Key") { showActivation = true }
                        .buttonStyle(LicenseButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func activate() {
        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true; error = ""
        Task {
            do { try await viewModel.activateLicense(key: licenseKey); showActivation = false; licenseKey = "" }
            catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

struct LicenseButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    var isDanger: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(isPrimary ? .white.opacity(0.1) : .clear).stroke(.white.opacity(isPrimary ? 0.15 : 0.08), lineWidth: 1))
            .foregroundStyle(isDanger ? .red.opacity(0.8) : (isPrimary ? .primary : .secondary))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
