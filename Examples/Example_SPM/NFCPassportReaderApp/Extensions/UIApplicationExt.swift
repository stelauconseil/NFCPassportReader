//
//  UIApplicationExt.swift
//  NFCPassportReaderApp
//
//  Created by Andy Qua on 20/01/2021.
//  Copyright © 2021 Andy Qua. All rights reserved.
//

import UIKit

extension UIApplication {
    static var release: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "x.x"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "x"
    }

    static var version: String {
        "\(release).\(build)"
    }
}
