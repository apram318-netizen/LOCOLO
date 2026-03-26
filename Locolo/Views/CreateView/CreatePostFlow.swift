//
//  CreatePostFlow.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import SwiftUI
import PhotosUI
import CoreLocation

struct CreatePostFlow: View {
    // MARK: Flow State
    @State private var step: CreateStep = .chooseType
    @State private var type: ContributionType?

    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var createPostVM: CreatePostViewModel
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            // MARK: Flow Steps
            switch step {
            
            // MARK: Step 1 — Choose Type
            case .chooseType:
                ChooseTypeScreen { chosen in
                    type = chosen
                    step = .media
                }
                .environmentObject(createPostVM)

            // MARK: Step 2 — Upload Media / AR Asset
            case .media:
                if type == .digitalAsset {
                    ARPostView(selectedTab: $selectedTab)
                } else {
                    MediaScreen(screenType: type!) {
                        step = .loop
                    }
                    .environmentObject(createPostVM)
                }

            // MARK: Step 3 — Choose Loop
            case .loop:
                LoopSelectionScreen {
                    step = .postDetails
                }

            // MARK: Step 4 — Post Details
            case .postDetails:
                PostDetailsScreen {
                    step = .preview
                }
                .environmentObject(createPostVM)
                .environmentObject(placeVM)

            // MARK: Step 5 — Place Details Flow
            case .placeDetails:
                PlaceDetailsScreen(
                    onDatabasePlaceSelected: { step = .memoryPrivacy },
                    onAppleMapPlaceSelected: { step = .completeMapPlace }
                )
                .environmentObject(placeVM)
                .environmentObject(createPostVM)

            case .completeMapPlace:
                CompleteMapPlaceScreen {
                    step = .memoryPrivacy
                }

            // MARK: Step 6 — Memory & Privacy
            case .memoryPrivacy:
                MemoryScreen {
                    step = .preview
                }

            // MARK: Step 7 — Final Preview
            case .preview:
                PreviewScreen()
                    .environmentObject(createPostVM)
            }
        }
    }
}

// MARK: - Types
enum ContributionType: String, CaseIterable {
    case placePost
    case digitalAsset
}

enum CreateStep {
    case chooseType
    case media
    case loop
    case postDetails
    case placeDetails
    case completeMapPlace
    case memoryPrivacy
    case preview
}

// MARK: - Choose Type Screen
struct ChooseTypeScreen: View {
    let onSelect: (ContributionType) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("What’s your vibe today?")
                .font(.title2).bold()

            Button("📍 Found a Spot (Place)") {
                onSelect(.placePost)
            }
            .buttonStyle(ContributionButtonStyle())

            Button("🎨 Dropping a Digital Flex") {
                onSelect(.digitalAsset)
            }
            .buttonStyle(ContributionButtonStyle())
        }
        .padding()
    }
}

// MARK: - Button Style
struct ContributionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(configuration.isPressed ? 0.6 : 0.9))
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}

