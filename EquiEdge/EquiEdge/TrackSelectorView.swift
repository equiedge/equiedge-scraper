import SwiftUI

struct TrackInfo {
    let name: String
    let slug: String
}

struct StateGroup {
    let state: String
    let tracks: [TrackInfo]
}

@Observable
final class TrackSelection {
    static let shared = TrackSelection()
    
    var selectedSlugs: Set<String> {
        didSet { save() }
    }
    
    static let allTrackGroups: [StateGroup] = [
        StateGroup(state: "New South Wales", tracks: [
            TrackInfo(name: "Royal Randwick", slug: "randwick"),
            TrackInfo(name: "Rosehill Gardens", slug: "rosehill"),
            TrackInfo(name: "Warwick Farm", slug: "warwick-farm"),
            TrackInfo(name: "Canterbury Park", slug: "canterbury"),
            TrackInfo(name: "Kembla Grange", slug: "kembla-grange"),
            TrackInfo(name: "Newcastle", slug: "newcastle"),
            TrackInfo(name: "Hawkesbury", slug: "hawkesbury"),
            TrackInfo(name: "Gosford", slug: "gosford"),
            TrackInfo(name: "Wyong", slug: "wyong"),
            TrackInfo(name: "Bathurst", slug: "bathurst"),
            TrackInfo(name: "Orange", slug: "orange"),
            TrackInfo(name: "Dubbo", slug: "dubbo"),
            TrackInfo(name: "Tamworth", slug: "tamworth"),
            TrackInfo(name: "Goulburn", slug: "goulburn"),
            TrackInfo(name: "Wagga Wagga", slug: "wagga"),
            TrackInfo(name: "Albury", slug: "albury"),
            TrackInfo(name: "Coffs Harbour", slug: "coffs-harbour"),
            TrackInfo(name: "Lismore", slug: "lismore"),
            TrackInfo(name: "Grafton", slug: "grafton"),
            TrackInfo(name: "Armidale", slug: "armidale"),
            TrackInfo(name: "Mudgee", slug: "mudgee"),
            TrackInfo(name: "Parkes", slug: "parkes"),
            TrackInfo(name: "Scone", slug: "scone"),
            TrackInfo(name: "Queanbeyan", slug: "queanbeyan"),
        ]),
        StateGroup(state: "Victoria", tracks: [
            TrackInfo(name: "Flemington", slug: "flemington"),
            TrackInfo(name: "Caulfield", slug: "caulfield"),
            TrackInfo(name: "Moonee Valley", slug: "moonee-valley"),
            TrackInfo(name: "Sandown", slug: "sandown"),
            TrackInfo(name: "Bendigo", slug: "bendigo"),
            TrackInfo(name: "Ballarat", slug: "ballarat"),
            TrackInfo(name: "Geelong", slug: "geelong"),
            TrackInfo(name: "Mornington", slug: "mornington"),
            TrackInfo(name: "Pakenham", slug: "pakenham"),
            TrackInfo(name: "Sale", slug: "sale"),
            TrackInfo(name: "Wodonga", slug: "wodonga"),
            TrackInfo(name: "Seymour", slug: "seymour"),
            TrackInfo(name: "Echuca", slug: "echuca"),
            TrackInfo(name: "Hamilton", slug: "hamilton"),
            TrackInfo(name: "Warrnambool", slug: "warrnambool"),
            TrackInfo(name: "Cranbourne", slug: "cranbourne"),
        ]),
        StateGroup(state: "Queensland", tracks: [
            TrackInfo(name: "Eagle Farm", slug: "eagle-farm"),
            TrackInfo(name: "Doomben", slug: "doomben"),
            TrackInfo(name: "Sunshine Coast", slug: "sunshine-coast"),
            TrackInfo(name: "Gold Coast", slug: "gold-coast"),
            TrackInfo(name: "Toowoomba", slug: "toowoomba"),
            TrackInfo(name: "Ipswich", slug: "ipswich"),
            TrackInfo(name: "Rockhampton", slug: "rockhampton"),
            TrackInfo(name: "Townsville", slug: "townsville"),
            TrackInfo(name: "Cairns", slug: "cairns"),
            TrackInfo(name: "Mackay", slug: "mackay"),
            TrackInfo(name: "Bundaberg", slug: "bundaberg"),
            TrackInfo(name: "Emerald", slug: "emerald"),
        ]),
        StateGroup(state: "South Australia", tracks: [
            TrackInfo(name: "Morphettville", slug: "morphettville"),
            TrackInfo(name: "Gawler", slug: "gawler"),
            TrackInfo(name: "Murray Bridge", slug: "murray-bridge"),
            TrackInfo(name: "Port Augusta", slug: "port-augusta"),
            TrackInfo(name: "Oakbank", slug: "oakbank"),
            TrackInfo(name: "Mount Gambier", slug: "mount-gambier"),
        ]),
        StateGroup(state: "Western Australia", tracks: [
            TrackInfo(name: "Ascot", slug: "ascot"),
            TrackInfo(name: "Belmont Park", slug: "belmont"),
            TrackInfo(name: "Gloucester Park", slug: "gloucester-park"),
            TrackInfo(name: "Pinjarra", slug: "pinjarra"),
            TrackInfo(name: "Bunbury", slug: "bunbury"),
            TrackInfo(name: "Albany", slug: "albany"),
            TrackInfo(name: "Kalgoorlie", slug: "kalgoorlie"),
            TrackInfo(name: "Geraldton", slug: "geraldton"),
        ]),
        StateGroup(state: "Tasmania", tracks: [
            TrackInfo(name: "Elwick (Hobart)", slug: "hobart"),
            TrackInfo(name: "Mowbray (Launceston)", slug: "launceston"),
            TrackInfo(name: "Devonport", slug: "devonport"),
            TrackInfo(name: "Spreyton", slug: "spreyton"),
        ]),
        StateGroup(state: "Northern Territory", tracks: [
            TrackInfo(name: "Darwin Turf Club", slug: "darwin"),
            TrackInfo(name: "Alice Springs", slug: "alice-springs"),
        ]),
        StateGroup(state: "Australian Capital Territory", tracks: [
            TrackInfo(name: "Thoroughbred Park (Canberra)", slug: "canberra"),
        ]),
    ]
    
    static let totalTrackCount: Int = {
        allTrackGroups.reduce(0) { $0 + $1.tracks.count }
    }()
    
    private static let defaultSlugs: Set<String> = [
        "caulfield", "randwick", "flemington", "moonee-valley", "rosehill",
        "gold-coast", "doomben", "ascot", "eagle-farm"
    ]
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "selectedTracks"),
           let slugs = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.selectedSlugs = slugs
        } else {
            self.selectedSlugs = Self.defaultSlugs
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(selectedSlugs) {
            UserDefaults.standard.set(data, forKey: "selectedTracks")
        }
    }
    
    func isSelected(_ slug: String) -> Bool {
        selectedSlugs.contains(slug)
    }
    
    func toggle(_ slug: String) {
        if selectedSlugs.contains(slug) {
            selectedSlugs.remove(slug)
        } else {
            selectedSlugs.insert(slug)
        }
    }
    
    func selectAll(in group: StateGroup) {
        for track in group.tracks {
            selectedSlugs.insert(track.slug)
        }
    }
    
    func deselectAll(in group: StateGroup) {
        for track in group.tracks {
            selectedSlugs.remove(track.slug)
        }
    }
    
    func selectAll() {
        for group in Self.allTrackGroups {
            selectAll(in: group)
        }
    }
    
    func deselectAll() {
        selectedSlugs.removeAll()
    }
    
    func allSelected(in group: StateGroup) -> Bool {
        group.tracks.allSatisfy { selectedSlugs.contains($0.slug) }
    }
}

struct TrackSelectorView: View {
    @Bindable var selection = TrackSelection.shared
    
    var body: some View {
        List {
            ForEach(TrackSelection.allTrackGroups, id: \.state) { group in
                Section {
                    ForEach(group.tracks, id: \.slug) { track in
                        Toggle(track.name, isOn: Binding(
                            get: { selection.isSelected(track.slug) },
                            set: { _ in selection.toggle(track.slug) }
                        ))
                    }
                } header: {
                    HStack {
                        Text(group.state)
                        Spacer()
                        let allOn = selection.allSelected(in: group)
                        Button(allOn ? "Deselect" : "Select All") {
                            if allOn {
                                selection.deselectAll(in: group)
                            } else {
                                selection.selectAll(in: group)
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("Racetracks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select All") {
                        selection.selectAll()
                    }
                    Button("Deselect All") {
                        selection.deselectAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
