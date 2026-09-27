//
//  ARSnapshotRenderer.swift
//  Locolo
//
//  Turns a raw ARView snapshot into a share-ready image: a soft bottom
//  gradient carrying the LOCOLO wordmark, what's in frame, and the date.
//

import UIKit

enum ARSnapshotRenderer {
    static func render(_ snapshot: UIImage, caption: String?) -> UIImage {
        let size = snapshot.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.draw(in: CGRect(origin: .zero, size: size))

            let bandHeight = size.height * 0.2
            let band = CGRect(x: 0, y: size.height - bandHeight, width: size.width, height: bandHeight)
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                          UIColor.black.withAlphaComponent(0.65).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: band.minY),
                    end: CGPoint(x: 0, y: band.maxY),
                    options: []
                )
            }

            let margin = size.width * 0.05
            let wordmarkSize = size.width * 0.07
            let wordmark = NSAttributedString(string: "LOCOLO", attributes: [
                .font: roundedFont(size: wordmarkSize, weight: .heavy),
                .foregroundColor: UIColor.white,
                .kern: wordmarkSize * 0.08
            ])
            let wordmarkBounds = wordmark.size()
            let wordmarkOrigin = CGPoint(x: margin, y: size.height - margin - wordmarkBounds.height)
            wordmark.draw(at: wordmarkOrigin)

            // Brand gradient underline beneath the wordmark.
            let underline = CGRect(x: margin, y: wordmarkOrigin.y + wordmarkBounds.height * 0.92,
                                   width: wordmarkBounds.width, height: max(2, wordmarkSize * 0.08))
            let brand = [UIColor.systemPurple.cgColor, UIColor.systemPink.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: brand, locations: [0, 1]) {
                context.cgContext.saveGState()
                context.cgContext.clip(to: underline)
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: underline.minX, y: 0),
                    end: CGPoint(x: underline.maxX, y: 0),
                    options: []
                )
                context.cgContext.restoreGState()
            }

            let detailSize = size.width * 0.032
            var lines: [String] = []
            if let caption, !caption.isEmpty { lines.append(caption) }
            lines.append(Date().formatted(date: .abbreviated, time: .shortened) + " · seen in AR")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            let detail = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
                .font: roundedFont(size: detailSize, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ])
            let detailWidth = size.width - margin * 3 - wordmarkBounds.width
            let detailRect = detail.boundingRect(with: CGSize(width: detailWidth, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin], context: nil)
            detail.draw(in: CGRect(x: size.width - margin - detailWidth,
                                   y: size.height - margin - detailRect.height,
                                   width: detailWidth, height: detailRect.height))
        }
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
