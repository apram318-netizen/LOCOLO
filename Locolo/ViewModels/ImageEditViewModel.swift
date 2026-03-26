//
//  ImageEditViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 7/10/2025.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
class ImageEditViewModel: ObservableObject {
    
    @Published var originalImage: UIImage                // The unedited, original photo
    @Published var editedImage: UIImage

    // MARK: - Adjustment sliders
    @Published var brightness: Double = 0                // Range: -1 to 1 (standard)
    @Published var contrast: Double = 1                  // Default = 1 (neutral)
    @Published var saturation: Double = 1                // Default = 1 (neutral)
    @Published var exposure: Double = 0
    
    private let context = CIContext()
    
    
    // MARK: Init
    /// - Description: Sets up the view model with an image to edit.
    /// Both the original and edited images are initialized as the same until filters are applied.
    ///
    /// - Parameter image: The UIImage the user selected for editing.
    init(image: UIImage) {
        self.originalImage = image
        self.editedImage = image
    }

    // MARK: FUNCTION: applyFilters
    /// - Description: Applies all current adjustment sliders (brightness, contrast, saturation, exposure)
    ///   to the original image and updates the editedImage preview.
    ///
    /// - Discussion:
    ///   Uses Core Image filters (`colorControls` + `exposureAdjust`)
    ///   Could later be extended with blur, vignette, or tint filters.
    ///   Could also support real-time performance optimization via Metal context.
    func applyFilters() {
        guard let ciImage = CIImage(image: originalImage) else { return }
        
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = Float(saturation)
        
        let exposureAdjust = CIFilter.exposureAdjust()
        exposureAdjust.inputImage = colorControls.outputImage
        exposureAdjust.ev = Float(exposure)
        
        guard let outputImage = exposureAdjust.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return
        }
        
        editedImage = UIImage(
            cgImage: cgImage,
            scale: originalImage.scale,
            orientation: originalImage.imageOrientation
        )
    }
    
    
    
    // MARK: FUNCTION: reset
    /// - Description: Resets all adjustment sliders to their default values and restores the original image.
    ///
    /// - Discussion:
    ///   Could later support undo/redo history.
    ///   Might also store presets so users can apply favorite filter combinations quickly.
    func reset() {
        brightness = 0
        contrast = 1
        saturation = 1
        exposure = 0
        editedImage = originalImage
    }
    
    
}

//Resources:
// https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/
// https://developer.apple.com/documentation/coreimage/cifilter
// https://stackoverflow.com/questions/42535219/adding-filter-to-images-swift // Most helpful, majorly just used this implementation along with some refinements
