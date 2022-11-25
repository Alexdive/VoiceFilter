//
//  UIButton+action.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 25.11.2022.
//

import UIKit

extension UIControl {
    func addAction(for controlEvents: UIControl.Event = .touchUpInside, _ closure: @escaping()->()) {
        addAction(UIAction { (action: UIAction) in closure() }, for: controlEvents)
    }
}
