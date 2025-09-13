import Foundation

// MARK: - Manager Wrapper Functions Extension

@available(macOS 11.0, *)
public extension KeysFFI {
    // MARK: - Mobile Manager Wrapper Functions

    func mobileInitializeUserRootKey() throws {
        try validateMobileManager().initializeUserRootKey()
    }

    func mobileGetUserPublicKey() throws -> Data {
        try validateMobileManager().getUserPublicKey()
    }

    func mobileProcessSetupToken(_ setupTokenCBOR: Data) throws -> Data {
        try validateMobileManager().processSetupToken(setupTokenCBOR: setupTokenCBOR)
    }

    func mobileRegisterDeviceKeystore(_ keystore: DeviceKeystoreType) throws {
        try validateMobileManager().registerDeviceKeystore(keystore)
    }

    func mobileGenerateNetworkDataKey() throws -> Data {
        try validateMobileManager().generateNetworkDataKey()
    }

    func mobileCreateNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPk: Data) throws -> Data {
        try validateMobileManager().createNetworkKeyMessage(networkPublicKey: networkPublicKey, nodeAgreementPk: nodeAgreementPk)
    }

    func mobileDeriveUserProfileKey(_ label: String) throws -> Data {
        try validateMobileManager().deriveUserProfileKey(label: label)
    }

    func mobileEncryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data {
        try validateMobileManager().encryptWithEnvelope(data: data, networkPublicKey: networkPublicKey, profileKeys: profileKeys)
    }

    func mobileDecryptMessageFromNode(_ encryptedMessage: Data) throws -> Data {
        try validateMobileManager().decryptMessageFromNode(encryptedMessage: encryptedMessage)
    }

    func mobileDecryptEnvelope(_ eedCbor: Data) throws -> Data {
        try validateMobileManager().decryptEnvelope(eedCbor: eedCbor)
    }

    func mobileInstallNetworkPublicKey(_ networkPublicKey: Data) throws {
        try validateMobileManager().installNetworkPublicKey(networkPublicKey: networkPublicKey)
    }

    // MARK: - Node Manager Wrapper Functions

    func nodeGetPublicKey() throws -> Data {
        try validateNodeManager().getPublicKey()
    }

    func nodeGetAgreementPublicKey() throws -> Data {
        try validateNodeManager().getAgreementPublicKey()
    }

    func nodeGenerateCSR() throws -> Data {
        try validateNodeManager().generateCSR()
    }

    func nodeInstallCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        try validateNodeManager().installCertificate(nodeCertificateMessageCBOR)
    }

    func nodeRegisterDeviceKeystore(_ keystore: DeviceKeystoreType) throws {
        try validateNodeManager().registerDeviceKeystore(keystore)
    }

    func nodeInstallNetworkKey(_ nkmCbor: Data) throws {
        try validateNodeManager().installNetworkKey(nkmCbor)
    }

    func nodeEncryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data {
        try validateNodeManager().encryptWithEnvelope(data: data, networkPublicKey: networkPublicKey, profileKeys: profileKeys)
    }

    func nodeEncryptLocalData(_ data: Data) throws -> Data {
        try validateNodeManager().encryptLocalData(data)
    }

    func nodeDecryptLocalData(_ encrypted: Data) throws -> Data {
        try validateNodeManager().decryptLocalData(encrypted)
    }

    func nodeDecryptMessageFromMobile(_ encryptedMessage: Data) throws -> Data {
        try validateNodeManager().decryptMessageFromMobile(encryptedMessage: encryptedMessage)
    }

    func nodeDecryptEnvelope(_ eedCbor: Data) throws -> Data {
        try validateNodeManager().decryptEnvelope(eedCbor: eedCbor)
    }

    func nodeGetNodeId() throws -> String {
        try validateNodeManager().getNodeId()
    }

    // MARK: - New Node Key Manager Functions

    /// Check if NodeKeyManager has keys
    func nodeHasKeys() throws -> Bool {
        try validateNodeManager().hasKeys()
    }

    /// Generate keys for NodeKeyManager
    func nodeGenerateKeys() throws {
        try validateNodeManager().generateKeys()
    }

    /// Get QUIC certificate configuration
    func nodeGetQuicCertificateConfig() throws -> Data {
        try validateNodeManager().getQuicCertificateConfig()
    }

    /// Get node certificate
    func nodeGetNodeCertificate() throws -> Data {
        try validateNodeManager().getNodeCertificate()
    }

    /// Get certificate status
    func nodeGetCertificateStatus() throws -> Int32 {
        try validateNodeManager().getCertificateStatus()
    }

    /// Get certificate serial number
    func nodeGetCertificateSerial() throws -> String {
        try validateNodeManager().getCertificateSerial()
    }

    /// Validate peer certificate
    func nodeValidatePeerCertificate(_ peerCert: Data) throws {
        try validateNodeManager().validatePeerCertificate(peerCert)
    }

    /// Get network agreement
    func nodeGetNetworkAgreement(networkPublicKey: Data) throws -> Data {
        try validateNodeManager().getNetworkAgreement(networkPublicKey: networkPublicKey)
    }

    /// Check if node has network private key
    func nodeHasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool {
        try validateNodeManager().hasNetworkPrivateKey(networkPublicKey: networkPublicKey)
    }

    /// Derive user profile key
    func nodeDeriveUserProfileKey(_ label: String) throws -> Data {
        try validateNodeManager().deriveUserProfileKey(label: label)
    }

    /// Decrypt envelope data using profile key
    func nodeDecryptWithProfile(envelopeData: Data, profileId: String) throws -> Data {
        try validateNodeManager().decryptWithProfile(envelopeData: envelopeData, profileId: profileId)
    }

    /// Install profile public key
    func nodeInstallProfilePublicKey(_ publicKey: Data) throws {
        try validateNodeManager().installProfilePublicKey(publicKey)
    }

    /// Get profile public key by label
    func nodeGetProfilePublicKeyByLabel(_ label: String) throws -> (publicKey: Data, hasKey: Bool) {
        try validateNodeManager().getProfilePublicKeyByLabel(label: label)
    }

    /// Get compact ID for public key
    func nodeGetCompactId(publicKey: Data) throws -> String {
        try validateNodeManager().getCompactId(publicKey: publicKey)
    }

    // MARK: - Convenience Functions

    func mobileSetPersistenceDirectory(_ directory: URL) throws {
        try setPersistenceDirectory(directory)
    }

    func mobileEnableAutoPersist(_ enabled: Bool) throws {
        try enableAutoPersist(enabled)
    }

    func nodeSetPersistenceDirectory(_ directory: URL) throws {
        try setPersistenceDirectory(directory)
    }

    func nodeEnableAutoPersist(_ enabled: Bool) throws {
        try enableAutoPersist(enabled)
    }

    // MARK: - Convenience Methods for E2E Tests

    /// Generate CSR (convenience method for E2E tests)
    func generateCSR() throws -> Data {
        try nodeGenerateCSR()
    }

    /// Install certificate (convenience method for E2E tests)
    func installCertificate(certificateMessage: Data) throws {
        try nodeInstallCertificate(certificateMessage)
    }

    /// From enroll response (convenience method for E2E tests)
    func fromEnrollResponse(enrollResponse: Data) throws -> Data {
        guard let mobileManager = try validateMobileManager() as? MobileKeyManagerImpl else {
            throw FFIError.wrongManagerType("Mobile manager is not MobileKeyManagerImpl")
        }
        return try mobileManager.fromEnrollResponse(enrollResponse)
    }

    /// From renew response (convenience method for E2E tests)
    func fromRenewResponse(renewResponse: Data) throws -> Data {
        guard let mobileManager = try validateMobileManager() as? MobileKeyManagerImpl else {
            throw FFIError.wrongManagerType("Mobile manager is not MobileKeyManagerImpl")
        }
        return try mobileManager.fromRenewResponse(renewResponse)
    }
}
