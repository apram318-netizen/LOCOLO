//
//  ARTabBar.swift
//  Locolo
//
//  Floating glass bottom bar for the standalone AR experience. Thin,
//  translucent, with a gradient pill that slides between the four tabs.
//

import SwiftUI

struct ARTabBar: View {
    @ObservedObject var dashboardState: ARDashboardState
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ARTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ARDesign.hairline, lineWidth: 1))
        .shadow(color: AppColors.cardShadow, radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AR World tabs")
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
