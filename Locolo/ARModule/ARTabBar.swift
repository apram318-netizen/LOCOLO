//
//  ARTabBar.swift
//  Locolo
//
//  Floating glass bottom bar for the standalone AR experience. Thin,
//  translucent, with a gradient pill that slides between the four tabs and
//  a raised Create button in the middle.
//

import SwiftUI

struct ARTabBar: View {
    @ObservedObject var dashboardState: ARDashboardState
    @Namespace private var indicator

    private var leading: [ARTab] { [.explore, .nearby] }
    private var trailing: [ARTab] { [.search, .profile] }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(leading) { tabButton($0) }
            createButton
            ForEach(trailing) { tabButton($0) }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ARDesign.hairline, lineWidth: 1))
        .shadow(color: AppColors.cardShadow, radius: 16, x: 0, y: 6)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loco AR tabs")
    }

    private var createButton: some View {
        Button {
            ARHaptics.success()
            dashboardState.path.append(.create)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle().fill(LinearGradient(colors: [.purple, .pink],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Color.pink.opacity(0.45), radius: 10, x: 0, y: 4)
                .offset(y: -10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel("Create AR asset")
    }

    private func tabButton(_ tab: ARTab) -> some View {
        let isActive = dashboardState.selectedTab == tab

        return Button {
            dashboardState.select(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isActive ? tab.filledIcon : tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: isActive)
                Text(tab.title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    Capsule()
                        .fill(LinearGradient(colors: [.purple, .pink],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .matchedGeometryEffect(id: "ar_tab_pill", in: indicator)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
