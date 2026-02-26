/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view that displays the list of available characters.
*/
import SwiftUI
import SpriteKit
import PhotosUI

struct ContentView: View {

    @State private var selection: EmojiRanger?
    @State private var navigationPath = NavigationPath()

    // MARK: - Master Portrait

    @State private var portraitItem: PhotosPickerItem?
    @State private var showPortraitRemoveConfirm = false
    @State private var portraitImage: UIImage? = MasterPortraitStore.load()
    @State private var isAutoSelecting = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(EmojiRanger.allHeros, id: \.self) { hero in
                NavigationLink(value: hero) {
                    TableRow(hero: hero)
                }
            }
            .onAppear {
                // Check for the most recently selected character.
                if let hero = try? EmojiRanger.getLastSelectedHero() {
                    print("Last character selection: \(hero)")
                }
            }
            .navigationBarTitle("Your Characters")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    MasterPortraitToolbarButton(
                        portraitImage: $portraitImage,
                        portraitItem: $portraitItem,
                        showRemoveConfirm: $showPortraitRemoveConfirm,
                        isAutoSelecting: $isAutoSelecting,
                        onAutoSelect: {
                            Task {
                                isAutoSelecting = true
                                portraitImage = await MasterPortraitStore.loadFromRecentPhotos(recentCount: 1000)
                                isAutoSelecting = false
                            }
                        }
                    )
                }
            }
            .onOpenURL(perform: { (url) in
                if let match = EmojiRanger.allHeros.compactMap({ hero in
                    url == hero.url ? hero : nil
                }).first {
                    navigationPath = NavigationPath([match])
                }
            })
            .navigationDestination(for: EmojiRanger.self) { hero in
                DetailView(hero: hero)
            }
        }
        // Save the picked photo to the App Group container (scaled to 108×108 px).
        // Must be done before starting a Live Activity — the widget extension
        // reads the file at render time via UIImage(contentsOfFile:).
        .onChange(of: portraitItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                MasterPortraitStore.save(image)
                portraitImage = MasterPortraitStore.load()
            }
        }
        .confirmationDialog(
            "Remove master portrait?",
            isPresented: $showPortraitRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                MasterPortraitStore.delete()
                portraitImage = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Master Portrait Toolbar Button

private struct MasterPortraitToolbarButton: View {

    @Binding var portraitImage: UIImage?
    @Binding var portraitItem: PhotosPickerItem?
    @Binding var showRemoveConfirm: Bool
    @Binding var isAutoSelecting: Bool
    let onAutoSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail or placeholder
            Group {
                if let img = portraitImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        .onLongPressGesture { showRemoveConfirm = true }
                } else if isAutoSelecting {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Manual pick
            PhotosPicker(
                selection: $portraitItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(portraitImage == nil ? "Set" : "Change")
                    .font(.caption)
            }
            .disabled(isAutoSelecting)

            // Auto-select best photo via Vision
            Button(action: onAutoSelect) {
                Label("Auto", systemImage: "sparkles")
                    .font(.caption)
            }
            .disabled(isAutoSelecting)
        }
    }
}

private struct TableRow: View {
    let hero: EmojiRanger
    var body: some View {
        HStack {
            Avatar(hero: hero)
            HeroNameView(hero)
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
