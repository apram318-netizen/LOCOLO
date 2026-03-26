//
//  ARDisplayView.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//
//  This screen shows the AR camera feed and the digital assets
//  placed around the user. It also shows a status message overlay
//  and a small green indicator once AR geo-tracking is fully ready.

import SwiftUI
import RealityKit
import ARKit

struct ARDisplayView: View {
    @StateObject private var vm = ARDisplayViewModel()
    
    var body: some View {
        ZStack {
            
            // MARK: - AR Camera View
            // Hosts the ARView from RealityKit and fills the whole screen.
            ARViewContainer(vm: vm)
                .edgesIgnoringSafeArea(.all)
            
            
            // MARK: - Localization Indicator
            // A green dot appears when the AR session is fully geo-localized.
            if vm.isLocalized {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .padding(.top, 50)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .transition(.scale)
            }
            
            
            // MARK: - Status Message
            // Shows helpful AR messages at the bottom (accuracy, loading, errors, etc).
            if let msg = vm.statusMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 40)
                }
                .animation(.easeInOut, value: msg)
            }
        }
        
        // MARK: - Startup
        // Resets AR state and begins location updates when the view appears.
        .onAppear {
            vm.resetARState()
            vm.startLocationUpdates()
        }
    }
}


// MARK: - ARView Container
// Wraps the shared ARView so SwiftUI can display RealityKit content.

struct ARViewContainer: UIViewRepresentable {
    let vm: ARDisplayViewModel
    
    func makeUIView(context: Context) -> ARView {
        let view = SharedARViewHolder.shared
        vm.arView = view
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}


// MARK: - Shared ARView
// Keeps one shared ARView instance so the AR session does not reset unnecessarily.
final class SharedARViewHolder {
    static let shared = ARView(frame: .zero)
}
