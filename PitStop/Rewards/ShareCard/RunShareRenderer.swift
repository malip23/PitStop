import MapKit
import SwiftUI

/// Builds the share image for a run:
/// 1. Optionally trims ~200 m off both ends of the route, so a shared run never reveals where you live.
/// 2. Takes a muted Apple Maps snapshot around the route and draws the route on it (soft glow + coral line,
///    destination dot).
/// 3. Renders `ShareCardView` with `ImageRenderer` at 3× → 1080×1350.
@MainActor
enum RunShareRenderer {
    static func image(for run: RunRecord, stamp: Stamp?, reward: EarnedReward?, hideEnds: Bool) async -> UIImage? {
        let route = trimmed(run.route.map(\.coordinate), by: hideEnds ? 200 : 0)
        let map = await mapImage(route: route, destination: hideEnds && run.routeShape == .oneWay ? nil : run.destinationPoint?.coordinate)

        let card = ShareCardView(
            mapImage: map,
            distance: Format.distance(run.distanceMeters),
            duration: Format.duration(run.durationSeconds),
            pace: "\(Format.pace(secondsPerMeter: run.averagePaceSecondsPerMeter)) \(Format.paceUnit)",
            activityName: run.activity.displayName,
            destinationName: run.destinationName,
            reward: reward.map { ($0.reward, $0.businessName) },
            stamp: stamp.map { ($0.placeName, $0.category, $0.earnedAt, $0.id) },
            verified: run.verification.passed,
            date: run.date)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Drops points within `meters` of the start and of the end.
    static func trimmed(_ coords: [CLLocationCoordinate2D], by meters: Double) -> [CLLocationCoordinate2D] {
        guard meters > 0, coords.count > 4, let first = coords.first, let last = coords.last else { return coords }
        let kept = coords.filter { $0.distance(to: first) > meters && $0.distance(to: last) > meters }
        return kept.count >= 2 ? kept : coords   // too short to trim: keep as is
    }

    private static func mapImage(route: [CLLocationCoordinate2D], destination: CLLocationCoordinate2D?) async -> UIImage? {
        guard route.count >= 2 else { return nil }
        let rect = MKPolyline(coordinates: route, count: route.count).boundingMapRect
        let padded = rect.insetBy(dx: -max(rect.width * 0.18, 300), dy: -max(rect.height * 0.18, 300))

        let options = MKMapSnapshotter.Options()
        options.mapRect = padded
        options.size = CGSize(width: 336, height: 200)
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.displayScale = 3
        }
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: options.size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            return format
        }())
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (index, coordinate) in route.enumerated() {
                let point = snapshot.point(for: coordinate)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let coral = UIColor(red: 0.99, green: 0.38, blue: 0.18, alpha: 1)
            coral.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 9
            path.stroke()
            coral.setStroke()
            path.lineWidth = 3.5
            path.stroke()

            if let destination {
                let p = snapshot.point(for: destination)
                let dot = UIBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                UIColor.white.setFill(); dot.fill()
                coral.setStroke(); dot.lineWidth = 2.5; dot.stroke()
            }
        }
    }
}
