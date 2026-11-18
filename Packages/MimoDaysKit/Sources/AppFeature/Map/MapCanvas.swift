import DesignSystem
import MapKit
import SwiftUI

/// `Map / Pin` and `Map / Cluster`: the newest photo in a cream frame, a coral count when more than one moment;
/// a coral ring when chosen (P02).
struct MapMarker: View {
    let image: UIImage?
    let count: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                MapPinFrameBlob()
                    .fill(ColorToken.actionCoral.color)
                    .frame(width: 66, height: 66)
            }
            MapPinFrameBlob()
                .fill(ColorToken.mediaFrame.color)
                .frame(width: 56, height: 56)
                .shadow(color: Color(hex: 0x4B2938).opacity(isSelected ? 0 : 0.18), radius: 4, y: 2)
            Color(hex: 0xB9A89A)
                .overlay { if let image { Image(uiImage: image).filling() } }
                .frame(width: 46, height: 46)
                .clipShape(MapPinPhotoBlob())
        }
        .frame(width: 66, height: 66)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text(count, format: .number)
                    .textStyle(.mapCount)
                    .foregroundStyle(ColorToken.mediaFrame.color)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(ColorToken.actionCoral.color))
                    .overlay(Capsule().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 2))
                    .fixedSize()
                    .offset(x: 2, y: -4)
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// One place on the map; MapKit clusters places that crowd each other.
final class PlaceAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let coverID: UUID
    let latest: Date
    let title: String?

    init(_ place: MapPlace) {
        id = place.id
        coordinate = place.coordinate
        count = place.moments.count
        coverID = place.moments.first?.id ?? UUID()
        latest = place.moments.first?.item.capturedAt ?? .distantPast
        title = place.label
    }
}

/// The marker as an annotation view, hosting the SwiftUI drawing.
final class MarkerView: MKAnnotationView {
    static let placeID = "place"
    static let clusterID = "cluster"
    private let host = UIHostingController(rootView: AnyView(MapMarker(image: nil, count: 1, isSelected: false)))

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 66, height: 66)
        host.view.backgroundColor = .clear
        host.view.frame = bounds
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
        collisionMode = .rectangle
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(image: UIImage?, count: Int, label: String, isSelected: Bool) {
        // Its own hosting controller doesn't inherit the app's faces: the cluster count gets them here.
        host.rootView = AnyView(MapMarker(image: image, count: count, isSelected: isSelected).environment(\.typefaces, Typefaces.current))
        accessibilityLabel = label
    }
}

/// P01's map: muted Apple map, places as photo markers, clusters while zoomed out. Choosing a place or a cluster
/// is reported; a cluster also zooms in on its places.
/// Holds a fit asked for before the first layout and runs it once the map has a size.
final class FittingMapView: MKMapView {
    var pendingFit: ((MKMapView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty, let fit = pendingFit else { return }
        pendingFit = nil
        fit(self)
    }
}

struct MapCanvas: UIViewRepresentable {
    let places: [MapPlace]
    let images: [UUID: UIImage]
    @Binding var selection: String?
    /// Bumped to fit every place again (filters changed, Locate without location).
    let fitToken: Int
    let showsUser: Bool
    /// What the places panel covers: the bottom on iPhone (P01's strip), the leading edge on iPad (X03). Fitting keeps
    /// every place clear of it.
    var cover = EdgeInsets()
    let onLoad: (UUID) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = FittingMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.delegate = context.coordinator
        map.showsCompass = false
        map.register(MarkerView.self, forAnnotationViewWithReuseIdentifier: MarkerView.placeID)
        map.register(MarkerView.self, forAnnotationViewWithReuseIdentifier: MarkerView.clusterID)
        map.pointOfInterestFilter = .excludingAll
        map.accessibilityIdentifier = "map.canvas"
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let wanted = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let current = map.annotations.compactMap { $0 as? PlaceAnnotation }
        let stale = current.filter { annotation in
            guard let place = wanted[annotation.id] else { return true }
            return place.moments.count != annotation.count || place.moments.first?.id != annotation.coverID
        }
        map.removeAnnotations(stale)
        let kept = Set(current.map(\.id)).subtracting(stale.map(\.id))
        map.addAnnotations(places.filter { !kept.contains($0.id) }.map(PlaceAnnotation.init))
        if coordinator.fitToken != fitToken {
            coordinator.fitToken = fitToken
            fit(map, coordinator: coordinator, leftToRight: context.environment.layoutDirection == .leftToRight)
        }
        map.showsUserLocation = showsUser
        if showsUser, coordinator.followsUser == false {
            coordinator.followsUser = true
            map.setUserTrackingMode(.follow, animated: true)
        } else if !showsUser {
            coordinator.followsUser = false
        }
        // Pictures arrive after the markers; selection can change from the sheet.
        for annotation in map.annotations {
            guard let view = map.view(for: annotation) as? MarkerView else { continue }
            coordinator.configure(view, for: annotation)
        }
        if selection == nil, !map.selectedAnnotations.isEmpty {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
        }
    }

    private func fit(_ map: MKMapView, coordinator: Coordinator, leftToRight: Bool) {
        // The first fit comes before the map has a size; fitting a 0×0 view shows the wrong region. It runs at the
        // first layout instead, with the cover known by then.
        if map.bounds.isEmpty, let map = map as? FittingMapView {
            map.pendingFit = { coordinator.parent.fit($0, coordinator: coordinator, leftToRight: leftToRight) }
            return
        }
        let annotations = map.annotations.compactMap { $0 as? PlaceAnnotation }
        guard !annotations.isEmpty else { return }
        // One place: 4 km around it.
        let side = annotations.count == 1 ? MKMapPointsPerMeterAtLatitude(annotations[0].coordinate.latitude) * 4_000 : 0
        let rect = annotations.map { MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 0, height: 0)) }
            .reduce(MKMapRect.null) { $0.union($1) }
            .insetBy(dx: -side / 2, dy: -side / 2)
        map.setVisibleMapRect(rect, edgePadding: Self.padding(cover, leftToRight), animated: false)
    }

    /// Room for a marker (about 60 pt) on every side, plus what the panel covers.
    static func padding(_ cover: EdgeInsets, _ leftToRight: Bool) -> UIEdgeInsets {
        let marker: CGFloat = 60
        return UIEdgeInsets(
            top: marker + cover.top,
            left: marker + (leftToRight ? cover.leading : cover.trailing),
            bottom: marker + cover.bottom,
            right: marker + (leftToRight ? cover.trailing : cover.leading)
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvas
        var fitToken = -1
        var followsUser = false

        init(_ parent: MapCanvas) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let place as PlaceAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MarkerView.placeID, for: place) as? MarkerView
                view?.clusteringIdentifier = "places"
                view?.displayPriority = .defaultHigh
                if let view { configure(view, for: place) }
                return view
            case let cluster as MKClusterAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MarkerView.clusterID, for: cluster) as? MarkerView
                view?.displayPriority = .required
                if let view { configure(view, for: cluster) }
                return view
            default:
                return nil
            }
        }

        func configure(_ view: MarkerView, for annotation: any MKAnnotation) {
            let members: [PlaceAnnotation]
            if let cluster = annotation as? MKClusterAnnotation {
                members = cluster.memberAnnotations.compactMap { $0 as? PlaceAnnotation }
            } else if let place = annotation as? PlaceAnnotation {
                members = [place]
            } else {
                return
            }
            guard let cover = members.max(by: { $0.latest < $1.latest }) else { return }
            let count = members.reduce(0) { $0 + $1.count }
            if parent.images[cover.coverID] == nil { parent.onLoad(cover.coverID) }
            let name = members.count == 1 ? (cover.title ?? String(appLocalized: "Unnamed place", bundle: .module)) : String(appLocalized: "\(members.count) places", bundle: .module)
            view.show(
                image: parent.images[cover.coverID], count: count,
                label: String(appLocalized: "Map marker: \(name) · \(String(appLocalized: "\(count) moments", bundle: .module))", bundle: .module),
                isSelected: members.count == 1 && parent.selection == cover.id
            )
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            } else if let place = annotation as? PlaceAnnotation {
                parent.selection = place.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
            if let place = annotation as? PlaceAnnotation, parent.selection == place.id { parent.selection = nil }
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: any Error) {
            parent.onFailure()
        }
    }
}
