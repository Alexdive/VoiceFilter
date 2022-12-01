//
//  UIButton+action.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 25.11.2022.
//

import UIKit

extension UIControl {
    func addAction(for controlEvents: UIControl.Event = .touchUpInside, _ closure: @escaping (UIControl.Event) -> Void) {
        addAction(UIAction { _ in closure(controlEvents) }, for: controlEvents)
    }
}

extension UIGestureRecognizer {
    func addTarget(_ closure: @escaping () -> Void) {
        @objc class ClosureSleeve: NSObject {
            let closure: () -> Void
            init(_ closure: @escaping () -> Void) { self.closure = closure }
            @objc func invoke() { closure() }
        }
        let sleeve = ClosureSleeve(closure)
        addTarget(sleeve, action: #selector(ClosureSleeve.invoke))
        objc_setAssociatedObject(self, "\(UUID())", sleeve, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
}

extension NotificationCenter {
    func addObserver(for name: NSNotification.Name, _ closure: @escaping () -> Void) {
        @objc class ClosureSleeve: NSObject {
            let closure: () -> Void
            init(_ closure: @escaping () -> Void) { self.closure = closure }
            @objc func invoke() { closure() }
        }
        let sleeve = ClosureSleeve(closure)
        addObserver(sleeve,
                    selector: #selector(ClosureSleeve.invoke),
                    name: name,
                    object: nil)
        objc_setAssociatedObject(self, "\(UUID())", sleeve, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
}
