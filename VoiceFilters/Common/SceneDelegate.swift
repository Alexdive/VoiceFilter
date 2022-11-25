//
//  SceneDelegate.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 23.11.2022.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window!.rootViewController = buildRootVC()
        window!.makeKeyAndVisible()
    }
    
    func buildRootVC() -> UIViewController {
        let avService = AVService()
        let presenter = MainViewPresenter(avService: avService)
        return MainViewController(presenter: presenter)
    }
}
