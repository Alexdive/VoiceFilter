//
//  Models.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 30.11.2022.
//

import UIKit

struct FilterName: Equatable, Hashable {
    var name: String
}

extension FilterName {
    static var highPitch: FilterName {
        .init(name: "highPitch")
    }
    static var lowPitch: FilterName {
        .init(name: "lowPitch")
    }
    static var alien: FilterName {
        .init(name: "alien")
    }
    static var reverb: FilterName {
        .init(name: "reverb")
    }
    static var none: FilterName {
        .init(name: "none")
    }
}

struct VoiceFilter: Hashable {
    var name: FilterName
    
    private var level: Float = 0
    
    var currentLevel: Float {
        get { level }
        set(newValue) { level = newValue }
    }
    
    init(name: FilterName, level: Float) {
        self.name = name
        self.currentLevel = level
    }
}

extension VoiceFilter: Equatable {
    static func == (lhs: VoiceFilter, rhs: VoiceFilter) -> Bool {
        lhs.name == rhs.name &&
        lhs.level == rhs.level
    }
}

extension VoiceFilter {
    static var highPitch: VoiceFilter {
        .init(name: .highPitch, level: 50)
    }
    static var lowPitch: VoiceFilter {
        .init(name: .lowPitch, level: 50)
    }
    static var alien: VoiceFilter {
        .init(name: .alien, level: 10)
    }
    static var reverb: VoiceFilter {
        .init(name: .reverb, level: 50)
    }
    static var none: VoiceFilter {
        .init(name: .none, level: 0)
    }
}

extension VoiceFilter {
    var config: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration.medium
    }
    
    var image: UIImage? {
        switch self {
        case .highPitch:
            return UIImage(systemName: "arrow.up.circle", withConfiguration: config)
        case .lowPitch:
            return UIImage(systemName: "arrow.down.circle", withConfiguration: config)
        case .alien:
            return UIImage(systemName: "ant.circle", withConfiguration: config)
        case .reverb:
            return UIImage(systemName: "building.columns.circle", withConfiguration: config)
        case .none:
            return UIImage(systemName: "xmark.circle", withConfiguration: config)
        default:
            return nil
        }
    }
    
    var selectedImage: UIImage? {
        switch self {
        case .highPitch:
            return UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        case .lowPitch:
            return UIImage(systemName: "arrow.down.circle.fill", withConfiguration: config)
        case .alien:
            return UIImage(systemName: "ant.circle.fill", withConfiguration: config)
        case .reverb:
            return UIImage(systemName: "building.columns.circle.fill", withConfiguration: config)
        case .none:
            return UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
        default:
            return nil
        }
    }
}
