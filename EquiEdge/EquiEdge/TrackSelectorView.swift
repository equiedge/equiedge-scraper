import SwiftUI

struct TrackInfo {
    let name: String
    let slug: String
}

enum TrackClassification: String, CaseIterable {
    case metro = "Metro"
    case provincial = "Provincial"
    case country = "Country"
}

struct StateGroup {
    let state: String
    let stateCode: String
    let tracks: [TrackInfo]
}

struct ClassificationGroup {
    let classification: TrackClassification
    let stateGroups: [StateGroup]

    var allTracks: [TrackInfo] {
        stateGroups.flatMap { $0.tracks }
    }
}

private func track(_ name: String) -> TrackInfo {
    TrackInfo(name: name, slug: name.lowercased().replacingOccurrences(of: " ", with: "-"))
}

@Observable
final class TrackSelection {
    static let shared = TrackSelection()

    var selectedSlugs: Set<String> {
        didSet { save() }
    }

    // MARK: - Track Data by Classification

    static let allClassificationGroups: [ClassificationGroup] = [
        // ── Metro ──
        ClassificationGroup(classification: .metro, stateGroups: [
            StateGroup(state: "New South Wales", stateCode: "NSW", tracks: [
                track("Randwick"),
                track("Randwick Kensington"),
                track("Rosehill"),
            ]),
            StateGroup(state: "Victoria", stateCode: "VIC", tracks: [
                track("Caulfield"),
                track("Caulfield Heath"),
                track("Flemington"),
                track("Sandown"),
            ]),
            StateGroup(state: "Queensland", stateCode: "QLD", tracks: [
                track("Doomben"),
                track("Eagle Farm"),
            ]),
            StateGroup(state: "South Australia", stateCode: "SA", tracks: [
                track("Morphettville"),
                track("Morphettville Parks"),
            ]),
            StateGroup(state: "Western Australia", stateCode: "WA", tracks: [
                track("Ascot"),
                track("Belmont"),
            ]),
            StateGroup(state: "Northern Territory", stateCode: "NT", tracks: [
                track("Darwin"),
            ]),
        ]),

        // ── Provincial ──
        ClassificationGroup(classification: .provincial, stateGroups: [
            StateGroup(state: "New South Wales", stateCode: "NSW", tracks: [
                track("Gosford"),
                track("Hawkesbury"),
                track("Newcastle"),
                track("Wyong"),
            ]),
            StateGroup(state: "Victoria", stateCode: "VIC", tracks: [
                track("Ballarat"),
                track("Ballarat Synthetic"),
                track("Bendigo"),
                track("Cranbourne"),
                track("Geelong"),
                track("Mornington"),
                track("Pakenham"),
                track("Pakenham Synthetic"),
            ]),
            StateGroup(state: "Queensland", stateCode: "QLD", tracks: [
                track("Gold Coast"),
                track("Gold Coast Polytrack"),
                track("Ipswich"),
                track("Mackay"),
                track("Rockhampton"),
                track("Sunshine Coast"),
                track("Sunshine Coast Cushion"),
                track("Sunshine Coast Polytrack"),
                track("Toowoomba"),
                track("Townsville"),
            ]),
            StateGroup(state: "Western Australia", stateCode: "WA", tracks: [
                track("Bunbury"),
                track("Geraldton"),
                track("Kalgoorlie"),
            ]),
        ]),

        // ── Country ──
        ClassificationGroup(classification: .country, stateGroups: [
            StateGroup(state: "New South Wales", stateCode: "NSW", tracks: [
                track("Albury"),
                track("Armidale"),
                track("Ballina"),
                track("Bathurst"),
                track("Berrigan"),
                track("Binnaway"),
                track("Boorowa"),
                track("Bourke"),
                track("Bowraville"),
                track("Braidwood"),
                track("Brewarrina"),
                track("Broken Hill"),
                track("Burrandowan"),
                track("Casino"),
                track("Cobar"),
                track("Coffs Harbour"),
                track("Cooma"),
                track("Coonabarabran"),
                track("Coonamble"),
                track("Cootamundra"),
                track("Corowa"),
                track("Cowra"),
                track("Deepwater"),
                track("Deniliquin"),
                track("Dubbo"),
                track("Forbes"),
                track("Gilgandra"),
                track("Glen Innes"),
                track("Goulburn"),
                track("Grafton"),
                track("Griffith"),
                track("Gulgong"),
                track("Gundagai"),
                track("Gunnedah"),
                track("Hillston"),
                track("Kempsey"),
                track("Leeton"),
                track("Lightning Ridge"),
                track("Lismore"),
                track("Merriwa"),
                track("Moree"),
                track("Moruya"),
                track("Mudgee"),
                track("Muswellbrook"),
                track("Narrabri"),
                track("Narrandera"),
                track("Narromine"),
                track("Narromine At Dubbo"),
                track("Nowra"),
                track("Nyngan"),
                track("Orange"),
                track("Parkes"),
                track("Port Macquarie"),
                track("Queanbeyan"),
                track("Quirindi"),
                track("Richmond"),
                track("Sapphire Coast"),
                track("Scone"),
                track("Tamworth"),
                track("Taree"),
                track("Tocumwal"),
                track("Tomingley"),
                track("Tullibigeal"),
                track("Tumbarumba"),
                track("Tumut"),
                track("Tuncurry"),
                track("Wagga"),
                track("Wagga Riverside"),
                track("Walcha"),
                track("Walgett"),
                track("Warialda"),
                track("Warren"),
                track("Wauchope"),
                track("Wellington"),
                track("Young"),
            ]),
            StateGroup(state: "Victoria", stateCode: "VIC", tracks: [
                track("Alexandra"),
                track("Ararat"),
                track("Avoca"),
                track("Bairnsdale"),
                track("Balnarring"),
                track("Benalla"),
                track("Buchan"),
                track("Camperdown"),
                track("Casterton"),
                track("Colac"),
                track("Coleraine"),
                track("Dederang"),
                track("Donald"),
                track("Drouin"),
                track("Dunkeld"),
                track("Echuca"),
                track("Edenhope"),
                track("Flinton"),
                track("Great Western"),
                track("Gunbower"),
                track("Hamilton"),
                track("Hanging Rock"),
                track("Healesville"),
                track("Hinnomunjie"),
                track("Horsham"),
                track("Kerang"),
                track("Kilmore"),
                track("Kyneton"),
                track("Mansfield"),
                track("Mildura"),
                track("Moe"),
                track("Mortlake"),
                track("Murtoa"),
                track("Penshurst"),
                track("Sale"),
                track("Seymour"),
                track("St Arnaud"),
                track("Stawell"),
                track("Stony Creek"),
                track("Swan Hill"),
                track("Swifts Creek"),
                track("Tatura"),
                track("Terang"),
                track("Towong"),
                track("Traralgon"),
                track("Tullibigeal"),
                track("Wangaratta"),
                track("Warracknabeal"),
                track("Warrnambool"),
                track("Werribee"),
                track("Wodonga"),
                track("Woolamai"),
                track("Wycheproof"),
                track("Yarra Valley"),
                track("Yea"),
            ]),
            StateGroup(state: "Queensland", stateCode: "QLD", tracks: [
                track("Aramac"),
                track("Atherton"),
                track("Augathella"),
                track("Barcaldine"),
                track("Beaudesert"),
                track("Bell"),
                track("Birdsville"),
                track("Blackall"),
                track("Bluff"),
                track("Boulia"),
                track("Bowen"),
                track("Bundaberg"),
                track("Burrumbeet"),
                track("Cairns"),
                track("Charleville"),
                track("Charters Towers"),
                track("Chinchilla"),
                track("Clermont"),
                track("Clifton"),
                track("Cloncurry"),
                track("Cooktown"),
                track("Cunnamulla"),
                track("Dalby"),
                track("Dingo"),
                track("Eidsvold"),
                track("Einasleigh"),
                track("Emerald"),
                track("Esk"),
                track("Gatton"),
                track("Gayndah"),
                track("Gladstone"),
                track("Goondiwindi"),
                track("Gordonvale"),
                track("Gympie"),
                track("Home Hill"),
                track("Hughenden"),
                track("Ilfracombe"),
                track("Ingham"),
                track("Injune"),
                track("Innisfail"),
                track("Isisford"),
                track("Jandowae"),
                track("Julia Creek"),
                track("Junction"),
                track("Jundah"),
                track("Kilcoy"),
                track("Kumbia"),
                track("Longreach"),
                track("Mareeba"),
                track("Maxwelton"),
                track("Mckinlay"),
                track("Miles"),
                track("Mitchell"),
                track("Monto"),
                track("Moranbah"),
                track("Mount Garnet"),
                track("Mount Isa"),
                track("Mount Perry"),
                track("Nanango"),
                track("Noorama"),
                track("Quilpie"),
                track("Roma"),
                track("Springsure"),
                track("St George"),
                track("Stanthorpe"),
                track("Surat"),
                track("Tambo"),
                track("Tara"),
                track("Taroom"),
                track("Thangool"),
                track("Wandoan"),
                track("Warra"),
                track("Warwick"),
                track("Winton"),
                track("Wondai"),
                track("Yeppoon"),
            ]),
            StateGroup(state: "South Australia", stateCode: "SA", tracks: [
                track("Balaklava"),
                track("Bordertown"),
                track("Ceduna"),
                track("Clare"),
                track("Gawler"),
                track("Jamestown"),
                track("Kangaroo Island"),
                track("Mount Barker"),
                track("Mount Gambier"),
                track("Murray Bridge"),
                track("Naracoorte"),
                track("Oakbank"),
                track("Penola"),
                track("Port Augusta"),
                track("Port Lincoln"),
                track("Quorn"),
                track("Roxby Downs"),
                track("Streaky Bay"),
                track("Strathalbyn"),
            ]),
            StateGroup(state: "Western Australia", stateCode: "WA", tracks: [
                track("Albany"),
                track("Broome"),
                track("Carnarvon"),
                track("Collie"),
                track("Derby"),
                track("Dongara"),
                track("Esperance"),
                track("Kojonup"),
                track("Kununurra"),
                track("Laverton"),
                track("Leinster"),
                track("Leonora"),
                track("Marble Bar"),
                track("Meekatharra"),
                track("Mingenew"),
                track("Moora"),
                track("Mount Magnet"),
                track("Narrogin"),
                track("Newman"),
                track("Northam"),
                track("Pingrup"),
                track("Pinjarra"),
                track("Pinjarra Scarpside"),
                track("Port Hedland"),
                track("Roebourne"),
                track("Toodyay"),
                track("York"),
            ]),
            StateGroup(state: "Tasmania", stateCode: "TAS", tracks: [
                track("Devonport"),
                track("Devonport Synthetic"),
                track("Hobart"),
                track("King Island"),
                track("Launceston"),
                track("Longford"),
            ]),
            StateGroup(state: "Northern Territory", stateCode: "NT", tracks: [
                track("Adelaide River"),
                track("Alice Springs"),
                track("Katherine"),
                track("Tennant Creek"),
            ]),
            StateGroup(state: "Australian Capital Territory", stateCode: "ACT", tracks: [
                track("Canberra"),
                track("Canberra Acton"),
            ]),
        ]),
    ]

    static let allTracks: [TrackInfo] = {
        allClassificationGroups.flatMap { $0.allTracks }
    }()

    static let totalTrackCount: Int = {
        allTracks.count
    }()

    private static let defaultSlugs: Set<String> = [
        "caulfield", "randwick", "flemington", "rosehill",
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

    // MARK: - State Group Selection

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

    func allSelected(in group: StateGroup) -> Bool {
        group.tracks.allSatisfy { selectedSlugs.contains($0.slug) }
    }

    // MARK: - Classification Group Selection

    func selectAll(inClassification group: ClassificationGroup) {
        for track in group.allTracks {
            selectedSlugs.insert(track.slug)
        }
    }

    func deselectAll(inClassification group: ClassificationGroup) {
        for track in group.allTracks {
            selectedSlugs.remove(track.slug)
        }
    }

    func allSelected(inClassification group: ClassificationGroup) -> Bool {
        group.allTracks.allSatisfy { selectedSlugs.contains($0.slug) }
    }

    // MARK: - Global Selection

    func selectAll() {
        for track in Self.allTracks {
            selectedSlugs.insert(track.slug)
        }
    }

    func deselectAll() {
        selectedSlugs.removeAll()
    }
}

// MARK: - View

struct TrackSelectorView: View {
    @Bindable var selection = TrackSelection.shared
    @State private var searchText = ""

    private var filteredClassificationGroups: [ClassificationGroup] {
        guard !searchText.isEmpty else {
            return TrackSelection.allClassificationGroups
        }
        return TrackSelection.allClassificationGroups.compactMap { classGroup in
            let filteredStateGroups = classGroup.stateGroups.compactMap { stateGroup -> StateGroup? in
                let filteredTracks = stateGroup.tracks.filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
                guard !filteredTracks.isEmpty else { return nil }
                return StateGroup(state: stateGroup.state, stateCode: stateGroup.stateCode, tracks: filteredTracks)
            }
            guard !filteredStateGroups.isEmpty else { return nil }
            return ClassificationGroup(classification: classGroup.classification, stateGroups: filteredStateGroups)
        }
    }

    var body: some View {
        List {
            ForEach(filteredClassificationGroups, id: \.classification) { classGroup in
                classificationToggleSection(classGroup)

                ForEach(classGroup.stateGroups, id: \.stateCode) { stateGroup in
                    stateSection(stateGroup)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search racetracks")
        .navigationTitle("Racetracks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select All") { selection.selectAll() }
                    Button("Deselect All") { selection.deselectAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func classificationToggleSection(_ classGroup: ClassificationGroup) -> some View {
        let allOn = selection.allSelected(inClassification: classGroup)
        Section {
            Toggle(isOn: Binding(
                get: { allOn },
                set: { newValue in
                    if newValue {
                        selection.selectAll(inClassification: classGroup)
                    } else {
                        selection.deselectAll(inClassification: classGroup)
                    }
                }
            )) {
                Text(classGroup.classification.rawValue)
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func stateSection(_ stateGroup: StateGroup) -> some View {
        Section {
            ForEach(stateGroup.tracks, id: \.slug) { track in
                Toggle(track.name, isOn: Binding(
                    get: { selection.isSelected(track.slug) },
                    set: { _ in selection.toggle(track.slug) }
                ))
            }
        } header: {
            HStack {
                Text(stateGroup.state)
                Spacer()
                let allOn = selection.allSelected(in: stateGroup)
                Button(allOn ? "Deselect" : "Select All") {
                    if allOn {
                        selection.deselectAll(in: stateGroup)
                    } else {
                        selection.selectAll(in: stateGroup)
                    }
                }
                .font(.caption)
                .textCase(nil)
            }
        }
    }
}
