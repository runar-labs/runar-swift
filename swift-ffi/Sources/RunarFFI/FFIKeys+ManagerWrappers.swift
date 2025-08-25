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

    func mobileRegisterDeviceKeystore(_ keystore: DeviceKeystore) throws {
        try validateMobileManager().registerDeviceKeystore(keystore)
    }

    func mobileGetKeystoreState() throws -> Int32 {
        try validateMobileManager().getKeystoreState()
    }

    func mobileGenerateNetworkDataKey() throws -> String {
        try validateMobileManager().generateNetworkDataKey()
    }

    func mobileGetNetworkPublicKey(_ networkId: String) throws -> Data {
        try validateMobileManager().getNetworkPublicKey(networkId)
    }

    func mobileCreateNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data {
        try validateMobileManager().createNetworkKeyMessage(networkId: networkId, nodeAgreementPk: nodeAgreementPk)
    }

    func mobileDeriveUserProfileKey(_ label: String) throws -> Data {
        try validateMobileManager().deriveUserProfileKey(label: label)
    }

    func mobileEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        try validateMobileManager().encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
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

    func nodeRegisterDeviceKeystore(_ keystore: DeviceKeystore) throws {
        try validateNodeManager().registerDeviceKeystore(keystore)
    }

    func nodeGetKeystoreState() throws -> Int32 {
        try validateNodeManager().getKeystoreState()
    }

    func nodeInstallNetworkKey(_ nkmCbor: Data) throws {
        try validateNodeManager().installNetworkKey(nkmCbor)
    }

    func nodeEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        try validateNodeManager().encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
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
}
