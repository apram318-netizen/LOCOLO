# Locolo

Locolo is a location-based social iOS app that organises communities around real geographic zones called **Loops** — neighbourhoods, campuses, and districts. Everything in the app is anchored to where you physically are: posts, events, places, AR digital assets, and real-time chat all tied to your local community.

---

## Features

### Loops
Geographic community zones automatically detected via GPS. The app uses PostGIS spatial queries to determine which Loop a user is in and tracks time spent in each one. Loops are bounded by real administrative boundaries fetched from the Overpass API (OpenStreetMap).

### Social Feed
Multiple post types tailored to context:
- **Standard posts** — text and media
- **Location posts** — tied to a specific place with a place card overlay
- **Event posts** — full event creation with pricing, dates, and attendee management
- **Real Memory** — BeReal-style authentic photo moments
- **Portal / Hover / Cloud posts** — location-specific shared experiences

### Engagement
- **Hype** — upvote system
- **Echo** — threaded comments and replies

### Discover
Browse and filter local places, events, and community activity. Places include images, categories, ratings, and a verification workflow.

### AR & Digital Assets
- View and place 3D digital assets in the real world using ARKit and RealityKit
- Full AR marketplace: create offers, negotiate pricing, manage a wishlist
- Panorama viewer for 360° context around asset locations

### Real-time Messaging
Firebase Firestore-powered chat with live message streaming, conversation management, user search, and per-user message deletion.

### Profile
User profiles with avatar, cover image, bio, stats (posts, followers, following), verification badges, and tabs for posts, visited places, and digital art collection.

### Location Tracking
Continuous background GPS tracking with smart visit confirmation (multi-tier: waiting → confirmed → reset). Location pings every 5 seconds when moving, 60 seconds when idle.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI, Combine |
| AR | ARKit, RealityKit, SceneKit |
| Maps | MapKit, Mapbox Maps iOS |
| Primary database | Supabase (PostgreSQL + PostGIS) |
| Real-time chat | Firebase Firestore |
| Authentication | Supabase Auth + Firebase Anonymous Auth |
| Location | CoreLocation, Overpass API, Google Places API |
| Caching | CoreData |
| Storage | Supabase Object Storage |

---

## Project Structure

```
Locolo/
├── Models/
│   ├── Controllers/        # Supabase, Google Places, Location, AR managers
│   ├── Repositories/       # Data access layer (Supabase + Firestore)
│   └── Cache/              # CoreData cache store and mapper
├── ViewModels/             # ObservableObject view models per feature
├── Views/
│   ├── LoginScreens/       # Auth flow (sign up, sign in, OTP, password reset)
│   ├── ExploreScreen/      # Feed, Loops, posts
│   ├── Discover Screen/    # Places, events, activities
│   ├── ARScreen/           # AR gallery, marketplace, offers
│   ├── CreateView/         # Post and AR asset creation flows
│   ├── Messages/           # Chat and conversation list
│   ├── ProfileScreen/      # User profile and tabs
│   └── SettingsScreen/     # Settings, edit profile, logout
└── LocoloNotificationService/  # Push notification extension
```

---

## Getting Started

### Requirements
- Xcode 15+
- iOS 17+
- Swift 5.9+
- Active Supabase project with PostGIS enabled
- Firebase project with Firestore and Authentication enabled
- Google Cloud project with Places API and Maps SDK enabled

### Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/apram318-netizen/LOCOLO.git
   cd LOCOLO
   ```

2. **Install dependencies**
   Open `Locolo.xcodeproj` in Xcode — Swift Package Manager will resolve dependencies automatically.

3. **Add secrets**
   Copy `Locolo/Secrets.example.swift` to `Locolo/Secrets.swift` and fill in your credentials:
   ```swift
   enum Secrets {
       static let supabaseURL      = "https://your-project.supabase.co"
       static let supabaseAnonKey  = "your-supabase-anon-key"
       static let googleMapsAPIKey = "your-google-maps-api-key"
   }
   ```
   Then add `Secrets.swift` to the Xcode target (drag it into the project navigator).

4. **Add Firebase config**
   Download `GoogleService-Info.plist` from your Firebase console and place it in the `Locolo/` folder. Add it to the Xcode target.

5. **Build and run**
   Select a simulator or device and hit Run.

---

## Environment Variables / Secrets

The following files are gitignored and must be provided locally:

| File | Purpose |
|---|---|
| `Locolo/Secrets.swift` | Supabase URL, anon key, Google Maps API key |
| `Locolo/GoogleService-Info.plist` | Firebase project configuration |

---

## Dependencies

Managed via Swift Package Manager:

- [Supabase Swift](https://github.com/supabase/supabase-swift) `2.32.0`
- [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk) `12.5.0`
- [Mapbox Maps iOS](https://github.com/mapbox/mapbox-maps-ios) `11.15.1`

---

## License

Private — all rights reserved.
