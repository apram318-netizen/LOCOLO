//
//  PlaceDetailsScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//



import SwiftUI
import PhotosUI
import CoreLocation

struct PlaceDetailsScreen: View {
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var locationVM = LocationViewModel()
    
    @EnvironmentObject var createPostVM: CreatePostViewModel
    
    let onDatabasePlaceSelected: () -> Void
    let onAppleMapPlaceSelected: () -> Void
    
    // MARK: Search State
    @State private var query: String = ""
    @State private var showAddNewForm = false
    @State private var showCompleteMapPlace = false

    var body: some View {
        let placeImageUrl = placeVM.uploadedMediaUrl
        
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Place Search or Add Form
                if !showAddNewForm {
                    PlaceSearchScreen(
                        query: $query,
                        placeVM: placeVM,
                        onNotFound: { showAddNewForm = true },
                        onSelect: { result in
                            placeVM.selectedPlace = result.place
                            createPostVM.selectedPlace = result.place //  sync into CreatePostVM
                            
                            switch result.source {
                            case .database:
                                onDatabasePlaceSelected()
                                
                            case .appleMap:
                                Task {
                                    if let loc = result.location {
                                        let savedLocation = try await locationVM.addLocation(loc)
                                        var newPlace = result.place
                                        newPlace?.locationId = savedLocation.id
                                        placeVM.selectedPlace = newPlace
                                        createPostVM.selectedPlace = newPlace //  mirror selectedPlace
                                        onAppleMapPlaceSelected()
                                    }
                                }
                            }
                        }
                    )
                } else {
                    AddNewPlaceSection(
                        loopVM: loopVM,
                        userVM: userVM,
                        locationVM: locationVM,
                        placeVM: placeVM,
                        createPostVM: createPostVM,  //  pass through to section
                        onNext: onDatabasePlaceSelected
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Place Details")
    }
}



struct PlaceSearchScreen: View {
    
    @Binding var query: String
    @ObservedObject var placeVM: PlaceViewModel
    
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var locationManager: LocationManager
    
    let onNotFound: () -> Void
    let onSelect: (PlaceResult) -> Void
    
    var body: some View {
        // MARK: Search Input Section
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search by name or address", text: $query)
            
            
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: query) { newValue in
                    Task {
                        if newValue.count > 3 {
                            let lat = locationManager.userLocation?.latitude
                            let lon = locationManager.userLocation?.longitude
                            
                            await placeVM.searchPlaceFlow(
                                query: newValue,
                                userLat: lat,
                                userLon: lon,
                                radiusMeters: 5000,
                                loopID: UUID(uuidString: loopVM.activeLoop?.id ?? ""),
                                postedBy: userVM.currentUser?.id
                            )
                        } else {
                            placeVM.placesResult = []
                        }
                    }
                }
            
            // MARK: Search Results Section
            if placeVM.isLoading {
                ProgressView("Searching…")
            }
            
            if !placeVM.placesResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(placeVM.placesResult, id: \.id ) { result in
                        Button {
                            onSelect(result)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.place?.name ?? "Unknown").bold()
                                
                                Text("Category: \(result.place?.categoryId?.uuidString ?? "N/A")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            } else if !query.isEmpty && !placeVM.isLoading {
                VStack(spacing: 12) {
                    Text("Looks like you discovered a new spot 🌟")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Nahh.. can’t find it 🚀") {
                        onNotFound()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
}




// MARK: - Small, typed subviews (keep the compiler happy)

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.headline)
    }
}



private struct PlaceNameField: View {
    @Binding var text: String
    var body: some View {
        TextField("Place name", text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
    }
}



private struct AddressSearchField: View {
    @Binding var address: String
    let onChange: (String) -> Void

    var body: some View {
        TextField("Address", text: $address)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onChange(of: address, perform: onChange)
    }
}



private struct AddressResultsList: View {
    let locations: [Location]
    let onPick: (Location) -> Void

    var body: some View {
        if !locations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(locations) { loc in
                    Button {
                        onPick(loc)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(loc.address).bold()
                            if let lat = loc.latitude as? Double,
                               let lon = loc.longitude as? Double {
                                Text("Lat: \(lat), Lon: \(lon)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
}




private struct CategoryPicker: View {
    @Binding var selected: String
    var body: some View {
        Picker("Category", selection: $selected) {
            Text("Restaurant").tag("restaurant")
            Text("Café").tag("cafe")
            Text("Park").tag("park")
            Text("Gym").tag("gym")
            Text("Sightseeing").tag("sightseeing")
        }
        .pickerStyle(MenuPickerStyle())
        // TODO(LOCOLO): Map category string to UUID | Status: Uncompleted
    }
}



private struct DescriptionEditor: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3))
            )
    }
}



private struct AddPlaceButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Add Place 🎉")
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(enabled ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!enabled)
    }
}



//TODO(LOCOLO): Change the location mapping of the postgre server |Status: Uncompleted

// TODO(LOCOLO): Change this to the button to submit the search and then do the google finding| Status: Uncompleted




struct AddNewPlaceSection: View {
    
    @ObservedObject var loopVM: LoopViewModel
    @ObservedObject var userVM: UserViewModel
    @ObservedObject var locationVM: LocationViewModel
    @ObservedObject var placeVM: PlaceViewModel
    @ObservedObject var createPostVM: CreatePostViewModel   
    
    let onNext: () -> Void
    
    // MARK: Form State
    @State private var placeName = ""
    @State private var showLocationEntry = false
    @State private var showAddImageView = false
    
    private var canAdd: Bool {
        !placeName.isEmpty && locationVM.selectedLocation != nil
    }
    
    var body: some View {
        // MARK: Place Form Section
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a new place 📍")
                .font(.headline)
            
            // MARK: Place Name Input
            TextField("Place name", text: $placeName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            // MARK: Image Selection Button
            Button {
                showAddImageView = true
            } label: {
                HStack {
                    Image(systemName: placeVM.uploadedMediaUrl == nil ? "photo.badge.plus" : "checkmark.seal.fill")
                        .foregroundColor(placeVM.uploadedMediaUrl == nil ? .pink : .green)
                    Text(placeVM.uploadedMediaUrl == nil ? "Add Image or Media" : "Image Added ")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .sheet(isPresented: $showAddImageView) {
                AddPlaceImageView(placeVM: placeVM)
            }
            
            // MARK: Location Selection Button
            Button(action: { showLocationEntry = true }) {
                HStack {
                    Image(systemName: "map")
                    Text(locationVM.selectedLocation == nil ? "Add / Pick Location" : "Change Location")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .sheet(isPresented: $showLocationEntry) {
                LocationEntryView { newLocation in
                    locationVM.selectedLocation = newLocation
                    showLocationEntry = false
                }
                .environmentObject(locationVM)
            }
            
            if let loc = locationVM.selectedLocation {
                VStack(alignment: .leading) {
                    Text("📍 \(loc.address)")
                    if let lat = loc.latitude, let lon = loc.longitude {
                        Text("Lat: \(lat), Lon: \(lon)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // MARK: Submit Button
            Button(action: addPlace) {
                Text("Add Place 🎉")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAdd ? Color.blue : Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!canAdd)
        }
        .padding(.horizontal)
    }
    
    // MARK: Place Creation Logic
    private func addPlace() {
        Task {
            guard let selectedLoc = locationVM.selectedLocation,
                  let activeLoop = loopVM.activeLoop,
                  let currentUser = userVM.currentUser else { return }
            
            let postNewPlace = PostPlace(
                id: UUID(),
                loopID: UUID(uuidString: activeLoop.id ?? ""),
                postedBy: currentUser.id,
                name: placeName,
                categoryId: nil,
                description: nil,
                placeImageUrl: placeVM.uploadedMediaUrl,
                trailerMediaUrl: nil,
                createdAt: Date(),
                locationId: selectedLoc.id,
                verificationStatus: "pending"
            )
            
            let newPlace = Place(
                id: UUID(),
                loopID: UUID(uuidString: activeLoop.id ?? ""),
                postedBy: currentUser.id,
                name: placeName,
                categoryId: nil,
                description: nil,
                placeImageUrl: placeVM.uploadedMediaUrl,
                trailerMediaUrl: nil,
                createdAt: Date(),
                locationId: selectedLoc.id,
                verificationStatus: "pending",
                score: 0
            )
            
            
            await placeVM.addPlace(postNewPlace)
            
            if placeVM.errorMessage == nil {
                //  sync new place + image into CreatePostVM
                
                createPostVM.selectedPlace = newPlace
                
                if let imageURL = placeVM.uploadedMediaUrl {
                    createPostVM.uploadedPlaceURL = URL(string: imageURL)
                }
                onNext()
            }
        }
    }
}




struct CompleteMapPlaceScreen: View {
    
    @EnvironmentObject var locationVM: LocationViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    
    let onNext: () -> Void

    @State private var category: String = ""
    @State private var description: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Complete details for this place 📍")
                    .font(.headline)

                if let selectedPlace = placeVM.selectedPlace {
                    Text(selectedPlace.name)
                        .font(.title2).bold()

                    if let loc = locationVM.selectedLocation {
                        Text(loc.address).foregroundColor(.secondary)
                    }
                }

                CategoryPicker(selected: $category)
                DescriptionEditor(text: $description)
                
                if placeVM.isLoading {
                    ProgressView("Saving…")
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                Button(action: savePlace) {
                    Text("Save Place 🎉")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.top, 20)
            }
            .padding()
        }
        .navigationTitle("Complete Place")
    }

    private func savePlace() {
        
        
        Task {
            guard let place = placeVM.selectedPlace else { return }
            
            
            let newPlace = PostPlace(
                id: UUID(),
                loopID: place.loopID,
                postedBy: place.postedBy,
                name: place.name,
                categoryId: nil,
                description: description,
                placeImageUrl: placeVM.uploadedMediaUrl,
                trailerMediaUrl: nil,
                createdAt: Date(),
                locationId: place.locationId,
                verificationStatus: place.verificationStatus
            )
            
            await placeVM.addPlace(newPlace)
            
            if placeVM.errorMessage == nil {
                onNext()
            }
        }
    }
}
