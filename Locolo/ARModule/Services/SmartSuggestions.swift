//
//  SmartSuggestions.swift
//  Locolo
//
//  Free, on-device intelligence — no API keys, no network, nothing leaves
//  the phone:
//    * Vision `VNClassifyImageRequest` — what's in a photo (scene labels) →
//      caption ideas + hashtags for memories, posts and new drops.
//    * NaturalLanguage — sentiment of comments / captions (gentle "this might
//      come across as harsh" nudge) and keyword extraction for tags.
//    * Apple Foundation Models (iOS 26+, Apple Intelligence devices) — short
//      natural captions and a one-line "why you might like this" for assets.
//      Silently falls back to Vision templates where unavailable.
//

import Foundation
import UIKit
import Vision
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

enum SmartSuggestions {

    // MARK: - Image understanding (Vision)

    /// Top scene labels for an image, most confident first ("sky", "graffiti").
    static func labels(for image: UIImage, limit: Int = 5) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            guard (try? handler.perform([request])) != nil,
                  let results = request.results else { return [] }
            return results
                .filter { $0.hasMinimumPrecision(0.6, forRecall: 0.4) }
                .prefix(limit)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
    }

    /// Hashtag ideas from an image (and optional caption text).
    static func hashtags(for image: UIImage?, text: String? = nil, limit: Int = 6) async -> [String] {
        var words: [String] = []
        if let image { words += await labels(for: image, limit: limit) }
        if let text { words += keywords(in: text) }
        var seen = Set<String>()
        return words
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { $0.count >= 3 && seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Captions

    /// 2–3 short caption ideas for a memory. Uses Foundation Models when the
    /// device supports Apple Intelligence, else Vision labels + templates.
    static func captionIdeas(for image: UIImage, assetName: String?) async -> [String] {
        let tags = await labels(for: image, limit: 4)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let generated = await generateCaptions(tags: tags, assetName: assetName) {
            return generated
        }
        #endif
        return templateCaptions(tags: tags, assetName: assetName)
    }

    private static func templateCaptions(tags: [String], assetName: String?) -> [String] {
        let name = assetName ?? "this drop"
        var ideas = ["Found \(name) ✨", "Caught \(name) in the wild"]
        if let first = tags.first { ideas.append("\(first.capitalized) vibes with \(name)") }
        return Array(ideas.prefix(3))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generateCaptions(tags: [String], assetName: String?) async -> [String]? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You write very short, upbeat social captions (max 8 words each) for photos \
            taken with augmented-reality art in public places. No hashtags. No quotes.
            """)
        let prompt = """
            AR artwork: \(assetName ?? "unnamed"). The photo shows: \(tags.joined(separator: ", ")).
            Give three different captions, one per line.
            """
        guard let response = try? await session.respond(to: prompt) else { return nil }
        let lines = response.content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. \"")) }
            .filter { !$0.isEmpty && $0.count <= 70 }
        return lines.isEmpty ? nil : Array(lines.prefix(3))
    }
    #endif

    /// One sentence on why an asset might appeal to the viewer, for the
    /// detail sheet ("Neon koi near the river — you've hyped 3 water pieces").
    static func whyYoullLikeIt(asset: DigitalAsset, likedCategories: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: "Write one friendly sentence (max 18 words). No emojis.")
            let prompt = """
                Recommend this AR artwork to a user. Title: \(asset.name ?? "untitled"). \
                Category: \(asset.categoryLabel ?? "art"). Description: \(asset.description ?? "none"). \
                The user often enjoys: \(likedCategories.joined(separator: ", ")).
                """
            if let r = try? await session.respond(to: prompt) {
                return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        #endif
        guard let cat = asset.normalizedCategory, likedCategories.contains(cat) else { return nil }
        return "Because you've been hyping \(asset.categoryLabel ?? cat) drops lately."
    }

    // MARK: - Text (NaturalLanguage)

    /// −1 (negative) … +1 (positive).
    static func sentiment(of text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return Double(tag?.rawValue ?? "0") ?? 0
    }

    /// True when a comment reads as clearly hostile — used for a soft
    /// "are you sure?" nudge before posting (never blocks).
    static func looksHarsh(_ text: String) -> Bool {
        text.count > 6 && sentiment(of: text) < -0.6
    }

    /// Nouns / names worth turning into tags.
    static func keywords(in text: String, limit: Int = 5) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if tag == .noun || tag == .placeName || tag == .personalName || tag == .organizationName {
                out.append(String(text[range]))
            }
            return out.count < limit
        }
        return out
    }
}
