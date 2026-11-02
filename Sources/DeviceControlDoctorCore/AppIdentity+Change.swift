import Foundation

public extension AppIdentity {
    /// Whether this reading differs from `baseline` in a way that can detach
    /// a permission grant from the app: designated requirement, signing
    /// identifier, team or signature validity. Only two finished signature
    /// checks are compared; a check that did not finish proves nothing.
    func hasChanged(from baseline: AppIdentity) -> Bool {
        guard baseline.signatureValid != nil, signatureValid != nil else { return false }
        return baseline.requirement != requirement
            || baseline.signingIdentifier != signingIdentifier
            || baseline.teamIdentifier != teamIdentifier
            || baseline.signatureValid != signatureValid
    }
}
