//
//  AROnboardingView.swift
//  Locolo
//
//  First-launch welcome: three quick pages that teach the core loop
//  (discover → create → connect) in the LOCOLO visual language.
//

import SwiftUI

struct AROnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(icon: "arkit",
             title: "Your world, in AR",
             body: "Walk around and discover 3D art placed by real people at real places. The radar in the AR view points you to what's nearby."),
        Page(icon: "hand.draw.fill",
             title: "Create anywhere",
             body: "Upload a 3D model — or pinch your fingers and draw one in the air. It stays exactly where you placed it, facing the way you left it."),
        Page(icon: "bubble.left.and.bubble.right.fill",
             title: "Connect, privately",
             body: "Follow creators, hype their work, and chat with end-to-end encryption. Only you and they can read your messages.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            LocoloWordmark(size: 30)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(AppColors.purplePinkGradient.opacity(0.16))
                                .frame(width: 130, height: 130)
                            Image(systemName: pages[i].icon)
                                .font(.system(size: 52))
                                .foregroundStyle(AppColors.purplePinkGradient)
                        }

                        Text(pages[i].title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(pages[i].body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(i)
                    .padding(.bottom, 40)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(ARDesign.spring) { page += 1 }
                } else {
                    ARHaptics.success()
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Enter the AR World")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(AppColors.purplePinkGradient))
                    .padding(.horizontal, 28)
            }

            Button("Skip") { onDone() }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 18)
                .opacity(page < pages.count - 1 ? 1 : 0)
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
