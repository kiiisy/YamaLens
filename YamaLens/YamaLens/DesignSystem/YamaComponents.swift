import SwiftUI
import UIKit

struct TopographicBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(YamaColor.canvas))

            for index in 0..<13 {
                var path = Path()
                let baseY = size.height * CGFloat(index) / 12
                path.move(to: CGPoint(x: -24, y: baseY))
                for step in 0...18 {
                    let x = size.width * CGFloat(step) / 18
                    let wave = sin(CGFloat(step) * 0.78 + CGFloat(index) * 0.61) * 13
                    path.addLine(to: CGPoint(x: x, y: baseY + wave))
                }
                context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MountainArtworkView: View {
    let mountain: Mountain
    var height: CGFloat = 176

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            MountainRidgeShape(phase: phase)
                .fill(.black.opacity(0.28))
                .frame(height: height * 0.72)

            MountainRidgeShape(phase: phase + 0.9)
                .fill(YamaColor.deepForest.opacity(0.74))
                .frame(height: height * 0.48)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private var phase: CGFloat {
        CGFloat(stableArtworkIndex % 7) * 0.31
    }

    private var artworkColors: [Color] {
        switch stableArtworkIndex % 3 {
        case 0: [Color(red: 0.13, green: 0.40, blue: 0.36), Color(red: 0.08, green: 0.14, blue: 0.13)]
        case 1: [Color(red: 0.37, green: 0.35, blue: 0.24), Color(red: 0.07, green: 0.14, blue: 0.12)]
        default: [Color(red: 0.18, green: 0.30, blue: 0.38), Color(red: 0.06, green: 0.12, blue: 0.11)]
        }
    }

    private var stableArtworkIndex: Int {
        mountain.id.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
    }
}

struct MountainHeroImageView: View {
    let mountain: Mountain
    let imageData: Data?
    let height: CGFloat

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                MountainArtworkView(mountain: mountain, height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct MountainRidgeShape: Shape {
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.72))

        for index in 0...10 {
            let ratio = CGFloat(index) / 10
            let peak = sin(ratio * .pi * 2.2 + phase) * rect.height * 0.10
            let crown = abs(sin(ratio * .pi * 1.35 + phase * 0.5)) * rect.height * 0.30
            path.addLine(to: CGPoint(x: rect.width * ratio, y: rect.height * 0.67 - crown + peak))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct YamaSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(YamaColor.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }
        }
    }
}

struct MountainPosterCard: View {
    let mountain: Mountain
    var badge: String?
    var heroImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MountainHeroImageView(
                mountain: mountain,
                imageData: heroImageData,
                height: 148
            )
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.52), in: Capsule())
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(mountain.name)
                    .font(.headline)
                    .foregroundStyle(YamaColor.primaryText)
                Text("\(mountain.elevationMeters.formatted())m ・ \(mountain.regionName)")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
            }
            .padding(13)
        }
        .frame(width: 220)
        .background(YamaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct YamaEmptyCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(YamaColor.moss)
                .frame(width: 46, height: 46)
                .background(YamaColor.moss.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(YamaColor.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
