//
//  LoopSelectionScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import SwiftUI
import PhotosUI
import CoreLocation

struct LoopSelectionScreen: View {
    @EnvironmentObject var loopVM: LoopViewModel
    @State private var selectedLoop: String?
    
    let onNext: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: Title Section
            titleSection
            // MARK: Loop Selection Section
            loopScrollSection
            Spacer()
            // MARK: Navigation Button
            nextButton
        }
        .padding()
        .navigationTitle("Select Loop")
    }
    
    private var titleSection: some View {
        Text("Where do you wanna drop this?")
            .font(.title2).bold()
            .padding(.top)
    }
    
    private var loopScrollSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(loopVM.userLoops, id: \.id) { loop in
                    LoopCard(
                        loop: loop,
                        isSelected: selectedLoop ==  loop.id
                    ) {
                        selectedLoop =  loop.id
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    
    private var nextButton: some View {
        Button(action: {
            if let selectedLoop = selectedLoop,
               let loop = loopVM.userLoops.first(where: { $0.id == selectedLoop }) {
                loopVM.setActiveLoop(loop)
                onNext()
            }
        }) {
            Text("Next ✨")
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedLoop != nil ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(selectedLoop == nil)
    }
}



struct LoopCard: View {
    let loop: Loop
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
                .overlay(Text(loop.name.prefix(2)).bold().foregroundColor(.white))
            
            Text(loop.name)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .onTapGesture { onTap() }
    }
}
