
import SwiftUI

struct EventDetailView: View {
    let event: EventItem
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                AsyncImage(url: URL(string: event.image)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(height: 220)
                .clipped()
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(event.name)
                        .font(.title).bold()
                    
                    Text(event.category)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.categoryBadge)
                        .cornerRadius(8)
                    
                    Label("\(event.date) • \(event.time)", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    HStack(spacing: 16) {
                        Label("\(event.attendees) attending", systemImage: "person.2.fill")
                        Label("\(event.hypes) hypes", systemImage: "sparkles")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    
                    Divider()
                    
                    Text(event.description)
                        .font(.body)
                        .foregroundColor(AppColors.primaryText)
                    
                    Divider()
                    
                    Button(action: {
                        if let url = URL(string: event.ticketUrl) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("Get Tickets", systemImage: "ticket.fill")
                            .font(.headline).bold()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(colors: [.purple, .pink],
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .cornerRadius(20)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(AppColors.cardBackground)
                .cornerRadius(16)
                .shadow(color: AppColors.cardShadow, radius: 5, x: 0, y: 2)
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

