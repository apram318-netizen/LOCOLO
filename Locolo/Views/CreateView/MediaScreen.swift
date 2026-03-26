//
//  MediaScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import SwiftUI
import PhotosUI

struct MediaScreen: View {
    
    @EnvironmentObject var createPostVM: CreatePostViewModel
    
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var editingVM: ImageEditViewModel?
    @State private var editingIndex: Int? = nil
    @State private var activeControl: EditControl? = nil

    var screenType: ContributionType
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            
            Group {
                if let vm = editingVM, let index = editingIndex {
                    FocusedEditSection(
                        vm: vm,
                        index: index,
                        selectedImages: $selectedImages,
                        editingVM: $editingVM,
                        editingIndex: $editingIndex,
                        activeControl: $activeControl
                    )
                } else if selectedImages.isEmpty {
                    VStack {
                        headerSection
                        pickerSection
                        
                        Spacer(minLength: 30)
                        nextButton
                    }
                } else {
                    VStack {
                        headerSection
                        previewSection
                    }
                    
                    Spacer(minLength: 30)
                    nextButton
                }
                
            }

        }
        .padding(.top, 20)
        .onChange(of: photoItems) { newItems in
            Task {
                selectedImages = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
            }
        }
        .animation(.spring(), value: selectedImages.count)
    }
}

extension MediaScreen {

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Add your memory 📸")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Choose, tweak, and vibe-check your photos before posting.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Picker
    private var pickerSection: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
            VStack(spacing: 8) {
                Image(systemName: "camera.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [.pink, .purple],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Tap to pick your memories")
                    .font(.headline)
                Text("(Up to 5 📸)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.pink.opacity(0.5))
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Image Preview Grid
    private var previewSection: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(radius: 3)
                                .onTapGesture {
                                    editingIndex = index
                                    editingVM = ImageEditViewModel(image: image)
                                }

                            Image(systemName: "slider.horizontal.3")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .offset(x: -8, y: -8)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Text("Tap any image to edit ✨")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Focused Edit Section
    struct FocusedEditSection: View {
        @ObservedObject var vm: ImageEditViewModel
        let index: Int

        @Binding var selectedImages: [UIImage]
        @Binding var editingVM: ImageEditViewModel?
        @Binding var editingIndex: Int?
        @Binding var activeControl: EditControl?

        var body: some View {
            VStack(spacing: 12) {
                
                EditImagePreview(vm: vm)
                    .padding(.top, 20)

                // Controls
                VStack(spacing: 8) {
                    EditControlsRow(activeControl: $activeControl)

                    if let control = activeControl {
                        EditSliderView(control: control, vm: vm)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    EditActionButtons(
                        index: index,
                        vm: vm,
                        selectedImages: $selectedImages,
                        editingVM: $editingVM,
                        editingIndex: $editingIndex,
                        activeControl: $activeControl
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color.white.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.25), value: activeControl)
        }
    }

    // MARK: - Large Image Preview
    struct EditImagePreview: View {
        @ObservedObject var vm: ImageEditViewModel

        var body: some View {
            ZStack {
                // Optional background to fill the rest of the space
                Color.white
                
                Image(uiImage: vm.editedImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Edit Controls Row
    
    struct EditControlsRow: View {
        @Binding var activeControl: EditControl?
        
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(EditControl.allCases, id: \.self) { control in
                        EditControlButton(
                            control: control,
                            isActive: activeControl == control
                        ) {
                            activeControl = control
                        }
                    }
                }
                .padding(.horizontal)
                
            }
        }
    }

    // MARK: - EditControlButton (fixes type-check issues)
   
    private struct EditControlButton: View {
        let control: EditControl
        let isActive: Bool
        let onTap: () -> Void
        
        var body: some View {
            VStack(spacing: 4) {
                Button(action: onTap) {
                    ZStack {
                        Circle()
                            .fill(
                                isActive
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.pink, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                  )
                                : AnyShapeStyle(Color(.systemGray5))
                            )
                            .frame(width: 56, height: 56)
                            .shadow(radius: isActive ? 5 : 0)
                        
                        Image(systemName: control.icon)
                            .font(.system(size: 22))
                            .foregroundColor(isActive ? .white : .primary)
                    }
                }
                Text(control.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    
    // MARK: - Slider for Active Control
    struct EditSliderView: View {
        let control: EditControl
        @ObservedObject var vm: ImageEditViewModel

        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    Text(control.title)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.2f", sliderValue(for: control)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                Slider(
                    value: binding(for: control),
                    in: control.range
                )
                .tint(.pink)
                .padding(.horizontal, 20)
                .onChange(of: binding(for: control).wrappedValue) { _ in
                    vm.applyFilters()
                }
            }
            .padding(.vertical, 6)
        }

        private func binding(for control: EditControl) -> Binding<Double> {
            switch control {
            case .brightness: return $vm.brightness
            case .contrast: return $vm.contrast
            case .saturation: return $vm.saturation
            case .exposure: return $vm.exposure
            }
        }

        private func sliderValue(for control: EditControl) -> Double {
            switch control {
            case .brightness: return vm.brightness
            case .contrast: return vm.contrast
            case .saturation: return vm.saturation
            case .exposure: return vm.exposure
            }
        }
    }

    
    // MARK: - Action Buttons
    struct EditActionButtons: View {
        let index: Int
        @ObservedObject var vm: ImageEditViewModel
        
        @Binding var selectedImages: [UIImage]
        @Binding var editingVM: ImageEditViewModel?
        @Binding var editingIndex: Int?
        @Binding var activeControl: EditControl?

        var body: some View {
            HStack(spacing: 20) {
                Button("Cancel") {
                    activeControl = nil
                    editingVM = nil
                    editingIndex = nil
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)
                
                Button("Apply ✨") {
                    selectedImages[index] = vm.editedImage
                    editingVM = nil
                    editingIndex = nil
                    activeControl = nil
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.pink, .purple],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    

    
    // MARK: - Slider for Active Control
    private func sliderFor(_ control: EditControl, vm: ImageEditViewModel) -> some View {
        VStack(spacing: 10) {
            Text(control.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            let binding: Binding<Double> = {
                switch control {
                case .brightness: return Binding(get: { vm.brightness }, set: { vm.brightness = $0 })
                case .contrast: return Binding(get: { vm.contrast }, set: { vm.contrast = $0 })
                case .saturation: return Binding(get: { vm.saturation }, set: { vm.saturation = $0 })
                case .exposure: return Binding(get: { vm.exposure }, set: { vm.exposure = $0 })
                }
            }()

            Slider(value: binding, in: control.range)
                .tint(.pink)
                .padding(.horizontal, 40)
                .onChange(of: binding.wrappedValue) { _ in vm.applyFilters() }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Next Button
    private var nextButton: some View {
        
        let backgroundView: AnyView = selectedImages.isEmpty
            ? AnyView(Color.gray.opacity(0.4))
            : AnyView(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))

        return Button(action: {
            createPostVM.memoryImages = selectedImages
            onNext()
        }) {
            Text(selectedImages.isEmpty ? "Add a Memory First" : "Next →")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(backgroundView)
        .foregroundColor(.white)
        .cornerRadius(14)
        .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 3)
        .disabled(selectedImages.isEmpty)
        .padding(.horizontal)
    }
    
    
}

// MARK: - EditControl Enum
enum EditControl: CaseIterable {
    case brightness, contrast, saturation, exposure

    var title: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .exposure: return "Exposure"
        }
    }

    var icon: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .contrast: return "circle.lefthalf.fill"
        case .saturation: return "drop.fill"
        case .exposure: return "camera.aperture"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -0.5...0.5
        case .contrast: return 0.5...2.0
        case .saturation: return 0.0...2.0
        case .exposure: return -1.0...1.0
        }
    }
}
