import Foundation

public struct SemanticVersion {

    /// The major version of the software
    public let major: Int

    /// The minor version of the software
    public let minor: Int?

    /// The patch version of the software
    public let patch: Int?

    public init(major: Int, minor: Int, patch: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    public init(major: Int, minor: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = nil
    }
}

extension SemanticVersion: RawRepresentable {

    public var rawValue: String {
        guard let minor else {
            return "\(major)"
        }
        guard let patch else {
            return "\(major).\(minor)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public init?(rawValue: String) {
        let parts = rawValue
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: ".")
        guard parts.count > 0 && parts.count < 4 else {
            return nil
        }
        guard let major = Int(parts[0]) else {
            return nil
        }
        guard parts.count > 1 else {
            return nil
        }
        guard let minor = Int(parts[1]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        guard parts.count > 2 else {
            self.patch = nil
            return
        }
        guard let patch = Int(parts[2]) else {
            return nil
        }
        self.patch = patch
    }
}

extension SemanticVersion: Decodable {

}

extension SemanticVersion: Encodable {

}

extension SemanticVersion: Equatable {

}

extension SemanticVersion: Hashable {

}

extension SemanticVersion: Comparable {

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major < rhs.major {
            return true
        }
        if lhs.major > rhs.major {
            return false
        }
        // Major version equal
        guard let lhsMinor = lhs.minor, let rhsMinor = rhs.minor else {
            return false
        }
        if lhsMinor < rhsMinor {
            return true
        }
        if lhsMinor > rhsMinor {
            return false
        }
        // Minor version equal
        guard let lhsPatch = lhs.patch, let rhsPatch = rhs.patch else {
            return false
        }
        return lhsPatch < rhsPatch
    }
}

extension SemanticVersion: MetricValue {
    
    public static let valueType: MetricType = .semanticVersion
}

extension SemanticVersion: CustomStringConvertible {
    
    public var description: String {
        rawValue
    }
}
