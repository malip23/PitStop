import SwiftUI

/// Business mode: create mock businesses and open each one's dashboard.
struct BusinessScreen: View {
    @Environment(AppState.self) private var app
    @State private var showCreate = false
    @State private var path: [Business.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if app.partners.isEmpty {
                    ContentUnavailableView {
                        Label("No businesses yet", systemImage: "storefront")
                    } description: {
                        Text("Create a mock business to demo Off-Peak Quests. Drop a pin, use your location, or link a real place nearby.")
                    } actions: {
                        Button("Create Mock Business") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(app.partners) { business in
                                NavigationLink(value: business.id) {
                                    MockBusinessRow(business: business)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets { app.deleteBusiness(id: app.partners[index].id) }
                            }
                        } header: {
                            Text("Your businesses")
                        } footer: {
                            Text("Tap a business to open its dashboard and tell runners you're slow.")
                        }
                    }
                }
            }
            .navigationTitle("Business")
            .navigationDestination(for: Business.ID.self) { id in
                BusinessDashboardView(businessID: id)
            }
            .toolbar {
                if !app.partners.isEmpty {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Create Mock Business", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                // After creating, jump straight into the new business's dashboard.
                MockBusinessEditor(existing: nil) { created in
                    path = [created.id]
                }
            }
        }
    }
}
