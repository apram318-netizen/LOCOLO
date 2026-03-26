//
//  NewLocationView.swift
//  Locolo
//
//  Created by Apramjot Singh on 23/9/2025.
//


import SwiftUI
import MapKit
import CoreLocation

struct LocationEntryView: View {
    @EnvironmentObject var locationManager: LocationManager
    
    @EnvironmentObject var locationVM : LocationViewModel
    
    // MARK: Form State
    @State private var placeName = ""
    @State private var streetAddress = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postcode = ""
    @State private var country = "Australia"
    @State private var googlePlaceId: String?
    @State private var showMapPicker = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    let onLocationAdded: (Location) -> Void
    
    private var canAddLocation: Bool {
        !placeName.isEmpty &&
        !streetAddress.isEmpty &&
        !city.isEmpty &&
        !state.isEmpty &&
        !postcode.isEmpty &&
        selectedCoordinate != nil
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add New Location 📍")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Enter the details for this new place")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // MARK: Form Section
                    VStack(alignment: .leading, spacing: 20) {
                        // MARK: Place Name Field
                        FormField(
                            title: "Place Name *",
                            placeholder: "e.g. Cozy Café, Central Park",
                            text: $placeName
                        )
                        
                        // MARK: Address Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Address Details")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            FormField(
                                title: "Street Address *",
                                placeholder: "123 Collins Street",
                                text: $streetAddress
                            )
                            
                            HStack(spacing: 12) {
                                FormField(
                                    title: "City *",
                                    placeholder: "Melbourne",
                                    text: $city
                                )
                                
                                FormField(
                                    title: "State *",
                                    placeholder: "VIC",
                                    text: $state
                                )
                            }
                            
                            HStack(spacing: 12) {
                                FormField(
                                    title: "Postcode *",
                                    placeholder: "3000",
                                    text: $postcode
                                )
                                
                                FormField(
                                    title: "Country",
                                    placeholder: "Australia",
                                    text: $country
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    
                    // Map Picker Option
                    Button(action: { showMapPicker = true }) {
                        HStack {
                            Image(systemName: "map")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Pick Location on Map")
                                    .font(.headline)
                                Text("Tap to select precise coordinates")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Selected Coordinates Display
                    if let coordinate = selectedCoordinate {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Location")
                                .font(.headline)
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Lat: \(coordinate.latitude, specifier: "%.6f"), Lon: \(coordinate.longitude, specifier: "%.6f")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Error Message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                
                
                Button(action: addLocation) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        Text(isLoading ? "Adding Location..." : "Add Location 🎉")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAddLocation && !isLoading ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canAddLocation || isLoading)
                .padding()
                .background(Color(.systemBackground))
            }
    
            .navigationTitle("New Location")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMapPicker) { // I need to remember here that this function is actually calling back from the map view struct I made
                MapPickerView(
                    initialCoordinate: selectedCoordinate ?? locationManager.userLocation,
                    onLocationSelected: { coordinate, placemark in
                        selectedCoordinate = coordinate
                        if let placemark = placemark {
                            streetAddress = [placemark.subThoroughfare, placemark.thoroughfare]
                                .compactMap { $0 }.joined(separator: " ")
                            city = placemark.locality ?? ""
                            state = placemark.administrativeArea ?? ""
                            postcode = placemark.postalCode ?? ""
                            country = placemark.country ?? "Australia"
                        }
                        showMapPicker = false
                    }
                )
            }
        }
    }
    
    private func addLocation() {
        
        guard let coordinate = selectedCoordinate else {
            errorMessage = "Please select a location on the map"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let newLocation = Location(
            id: UUID(),
            name: placeName,
            address: "\(streetAddress), \(city), \(state) \(postcode), \(country)",
            city: city ,
            country: country,
            googlePlaceId: googlePlaceId,
            geom: nil,
            similarityScore: 0,
            distMeters: 0,
            latitude: coordinate.latitude ,
            longitude: coordinate.longitude,
        )
        
        Task {
            do {
               let addedLocation = try await locationVM.addLocation(newLocation)
                
                await MainActor.run {
                    isLoading = false
                    onLocationAdded(addedLocation)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}



// MARK: - Supporting Components

struct FormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}



struct MapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}



// MARK: - Location Manager




struct MapPickerView: View {
    
    let initialCoordinate: CLLocationCoordinate2D?

    let onLocationSelected: (CLLocationCoordinate2D, CLPlacemark?) -> Void
    
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var addressText = "Tap on the map to drop a pin"
    @State private var isGeocoding = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tapable map
                TapableMapView(
                    initialCoordinate: initialCoordinate,
                    selectedCoordinate: $selectedCoordinate,
                    onCoordinateSelected: { coordinate in
                        selectedCoordinate = coordinate
                        reverseGeocode(coordinate)
                    }
                )
                .frame(maxHeight: .infinity)
                
                // Address Preview
                VStack(spacing: 12) {
                    if isGeocoding {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Getting address...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(addressText)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    
                    Button("Use This Location ✅") {
                        if let coordinate = selectedCoordinate  {
                            reverseGeocode(coordinate, completion: { placemark in
                                onLocationSelected(coordinate, placemark)
                                dismiss()
                            })
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedCoordinate != nil ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(selectedCoordinate == nil)
                }
                .padding()
            }
            .navigationTitle("Pick Location")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func reverseGeocode(
            _ coordinate: CLLocationCoordinate2D,
            completion: ((CLPlacemark?) -> Void)? = nil
    ) {
        isGeocoding = true
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                isGeocoding = false
                let placemark = placemarks?.first
                if let placemark = placemark {
                    addressText = [
                        placemark.subThoroughfare,
                        placemark.thoroughfare,
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.postalCode,
                        placemark.country
                    ].compactMap { $0 }.joined(separator: ", ")
                } else {
                    addressText = "Address not found"
                }
                completion?(placemark)
            }
        }
    }
    
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            components.append("\(streetNumber) \(streetName)")
        } else if let streetName = placemark.thoroughfare {
            components.append(streetName)
        }
        
        if let city = placemark.locality {
            components.append(city)
        }
        
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        
        if let postcode = placemark.postalCode {
            components.append(postcode)
        }
        
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
}




struct TapableMapView: UIViewRepresentable {
    
    let initialCoordinate: CLLocationCoordinate2D?
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    let onCoordinateSelected: (CLLocationCoordinate2D) -> Void
    
    @EnvironmentObject var locationManager: LocationManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        
        // Set to melb for now, I will change it later to probably the user's current location or something
        
        
        let center = locationManager.userLocation ?? CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
        
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: false)
        
        // Add tap recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Clear annotations
        uiView.removeAnnotations(uiView.annotations)
        
        // Add selected pin
        if let coordinate = selectedCoordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: TapableMapView
        
        init(_ parent: TapableMapView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            
            parent.selectedCoordinate = coordinate
            parent.onCoordinateSelected(coordinate)
        }
    }
}

