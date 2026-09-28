//
//  AROnboardingView.swift
//  Locolo
//
//  First-launch welcome: discover → create → connect → taste interests.
//

import SwiftUI

struct AROnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    @State private var selectedInterests: Set<String> = []

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

    private let interestChips = [
        "street", "sculpture", "neon", "nature", "music", "fashion",
        "meme", "abstract", "architecture", "animals", "sports", "night"
    ]

    private var isInterestsPage: Bool { page == pages.count }
    private var lastPageIndex: Int { pages.count } // interests is final

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

                interestsPage
                    .tag(pages.count)
                    .padding(.bottom, 24)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPageIndex {
                    withAnimation(ARDesign.spring) { page += 1 }
                } else {
                    persistInterests()
                    ARHaptics.success()
                    onDone()
                }
            } label: {
                Text(page < lastPageIndex ? "Next" : "Enter the AR World")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(AppColors.purplePinkGradient))
                    .padding(.horizontal, 28)
            }

            Button("Skip") {
                persistInterests()
                onDone()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.bottom, 18)
            .opacity(page < lastPageIndex ? 1 : 0)
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
        .task { await TagStore.shared.refreshTrending() }
    }

    private var interestsPage: some View {
        VStack(spacing: 16) {
            Text("What are you into?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Pick a few vibes — we'll seed your For You feed. You can change this any time by exploring.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            let chips: [String] = {
                let fromTags = TagStore.shared.trending.map(\.label)
                return Array((fromTags.isEmpty ? interestChips : fromTags).prefix(16))
            }()

            FlowInterestChips(options: chips, selected: $selectedInterests)
                .padding(.horizontal, 20)
        }
    }

    private func persistInterests() {
        let list = Array(selectedInterests).sorted()
        UserDefaults.standard.set(list, forKey: "ar.onboarding.interests")
    }
}

/// Simple wrapping chip row for onboarding interests.
private struct FlowInterestChips: View {
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        FlexibleChipWrap(options: options, selected: $selected)
    }
}

private struct FlexibleChipWrap: View {
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        // Two-column grid keeps layout simple without a custom Layout type.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { tag in
                let on = selected.contains(tag)
                Button {
                    ARHaptics.tick()
                    if on { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(on ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? AnyShapeStyle(AppColors.purplePinkGradient)
                                      : AnyShapeStyle(Color.adaptive(light: Color.black.opacity(0.06),
                                                                     dark: Color.white.opacity(0.08))))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
