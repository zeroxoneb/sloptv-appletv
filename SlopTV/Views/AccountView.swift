import CoreImage.CIFilterBuiltins
import SwiftUI

struct AccountView: View {
    private let account = AccountModel.shared
    @State private var signingIn = SlopTVApp.launchArgument("-signIn")

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: account.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                .font(.system(size: 140))
                .foregroundStyle(account.isSignedIn ? Theme.accent : Theme.muted)

            switch account.state {
            case .unknown:
                ProgressView()
            case let .signedIn(name):
                Text(name.map { "Signed in as \($0)" } ?? "Signed in to tv.slop.cc")
                    .font(.title2.bold())
                Text("Use 👍 in the player (swipe down while a film plays) or on a film's page.")
                    .foregroundStyle(Theme.muted)
                Button("Sign Out of This Apple TV", role: .destructive) { account.signOut() }
            case .signedOut, .expired:
                Text(account.state == .expired ? "Your tv.slop.cc session expired" : "Sign in to like films")
                    .font(.title2.bold())
                Text("Browsing and watching work without an account. Signing in lets you 👍 films on tv.slop.cc.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                Button { signingIn = true } label: {
                    Label("Sign In", systemImage: "qrcode").padding(.horizontal, 30)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .fullScreenCover(isPresented: $signingIn) { SignInView() }
    }
}

/// Shows the address of the local handoff page and waits for cookies to arrive.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var server: LinkServer?
    @State private var url: URL?
    @State private var error: String?
    @State private var signedInAs: String??

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let name = signedInAs {
                VStack(spacing: 30) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 140)).foregroundStyle(Theme.accent)
                    Text(name.map { "Signed in as \($0)" } ?? "Signed in").font(.title.bold())
                    Button("Done") { dismiss() }
                }
            } else if let url {
                HStack(alignment: .center, spacing: 100) {
                    VStack(alignment: .leading, spacing: 30) {
                        Text("Sign in to Slop TV").font(.system(size: 64, weight: .heavy))
                        step(1, "On a computer signed in to tv.slop.cc, open:")
                        Text(url.absoluteString)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.leading, 70)
                        step(2, "Follow the steps on that page to send your session to this Apple TV.")
                        step(3, "This screen updates as soon as you're signed in.")
                        Text("The computer must be on the same network as this Apple TV. The page closes when you leave this screen.")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 20)
                        Button("Cancel") { dismiss() }
                    }
                    .frame(maxWidth: 1000, alignment: .leading)

                    VStack(spacing: 16) {
                        QRCode(text: url.absoluteString)
                            .frame(width: 420, height: 420)
                            .padding(24)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        Text("Or scan to open the page").font(.callout).foregroundStyle(Theme.muted)
                    }
                }
                .padding(80)
            } else if let error {
                VStack(spacing: 30) {
                    Text("Couldn't start sign-in").font(.title.bold())
                    Text(error).foregroundStyle(Theme.muted)
                    Button("Close") { dismiss() }
                }
            } else {
                ProgressView()
            }
        }
        .task { await start() }
        .onDisappear { server?.stop() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text("\(n)")
                .font(.title3.bold())
                .frame(width: 46, height: 46)
                .background(Theme.raised, in: Circle())
            Text(text).font(.title3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() async {
        let server = LinkServer { pasted in
            do {
                let name = try await AccountModel.shared.signIn(pasted: pasted)
                await MainActor.run { signedInAs = .some(name) }
                return .success(name)
            } catch {
                return .failure(error)
            }
        }
        self.server = server
        do {
            url = try await server.start()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        }
    }

    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
