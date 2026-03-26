//
//  CustomMapView.swift
//  Locolo
//
//  Created by Apramjot Singh on 6/11/2025.
//


import SwiftUI
import MapKit

struct CustomMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var overlay: MKOverlay?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        
        //  Muted, clean world style: blue oceans + white borders, minimal detail
        if #available(iOS 16.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat)
            config.emphasisStyle = .muted
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        } else {
            mapView.mapType = .mutedStandard
        }
        
        //  Disable unnecessary interactions
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        
        //  Hide clutter
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsBuildings = false
        mapView.showsUserLocation = false
        
        //  Slightly dark mode for contrast
        mapView.overrideUserInterfaceStyle = .dark
        
        //  Set initial region
        mapView.region = region
        mapView.delegate = context.coordinator
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove old overlays first
        mapView.removeOverlays(mapView.overlays)
        
        // Add the selected overlay (can be MKPolygon or MKMultiPolygon)
        if let overlay = overlay {
            mapView.addOverlay(overlay)
            print(" Adding overlay to map: \(type(of: overlay))")
            
            // Zoom to show the overlay with padding
            let rect = overlay.boundingMapRect
            let insets = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
            mapView.setVisibleMapRect(rect, edgePadding: insets, animated: true)
            print(" Map rect set to: \(rect)")
        } else {
            // No overlay, just set the region
            mapView.setRegion(region, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView
        
        init(_ parent: CustomMapView) {
            self.parent = parent
        }
        
        //  Render the loop region polygon
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            print(" Renderer requested for: \(type(of: overlay))")
            
            // Handle regular polygon (single region)
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = UIColor.systemPurple
                renderer.fillColor = UIColor.systemPurple.withAlphaComponent(0.25)
                renderer.lineWidth = 3.0  // Thicker for visibility
                print(" Created MKPolygonRenderer with \(polygon.pointCount) points")
                return renderer
            }

            // Handle multi-polygon (multiple disconnected regions)
            if let multi = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
                renderer.strokeColor = UIColor.systemPurple
                renderer.fillColor = UIColor.systemPurple.withAlphaComponent(0.25)
                renderer.lineWidth = 3.0  // Thicker for visibility
                print(" Created MKMultiPolygonRenderer with \(multi.polygons.count) polygons")
                return renderer
            }

            // Fallback
            print(" Fallback renderer used for unknown overlay type")
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
