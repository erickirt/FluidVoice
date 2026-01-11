//
//  ModelRepository.swift
//  Fluid
//
//  Single source of truth for default model lists per provider.
//  All views (AISettings, ContentView, CommandMode, RewriteMode) should use this
//  instead of maintaining their own hardcoded lists.
//

import Foundation

final class ModelRepository {
    static let shared = ModelRepository()

    private init() {}

    /// Returns the default models for a given provider ID.
    /// This is used when the user has not added any custom models for that provider.
    func defaultModels(for providerID: String) -> [String] {
        switch providerID {
        case "openai":
            return ["gpt-4.1"]
        case "groq":
            return ["openai/gpt-oss-120b"]
        case "apple-intelligence":
            return ["System Model"]
        default:
            // Custom providers start with no default models; user must add them
            return []
        }
    }
}
