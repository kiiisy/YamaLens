import Foundation

enum MountainProximityText {
    static func summary(_ proximity: MountainProximity) -> String {
        guard let direction = proximity.direction else {
            return distance(proximity.distance)
        }
        return "\(directionName(direction)) \(distance(proximity.distance))"
    }

    static func distance(_ distance: MountainDistance) -> String {
        if distance.meters < 1_000 {
            return "\(Int(distance.meters.rounded()).formatted())m"
        }
        let kilometers = distance.meters / 1_000
        return "\(kilometers.formatted(.number.precision(.fractionLength(1))))km"
    }

    static func directionName(_ direction: CompassDirection) -> String {
        switch direction {
        case .north:
            return "北"
        case .northeast:
            return "北東"
        case .east:
            return "東"
        case .southeast:
            return "南東"
        case .south:
            return "南"
        case .southwest:
            return "南西"
        case .west:
            return "西"
        case .northwest:
            return "北西"
        }
    }
}
