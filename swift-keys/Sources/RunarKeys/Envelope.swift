import Foundation
import CryptoKit

public struct EnvelopeEncryptedData: Codable {
	public let encryptedData: Data
	public let networkId: String?
	public let networkEncryptedKey: Data
	public let profileEncryptedKeys: [String: Data]

	public init(encryptedData: Data, networkId: String?, networkEncryptedKey: Data, profileEncryptedKeys: [String: Data]) {
		self.encryptedData = encryptedData
		self.networkId = networkId
		self.networkEncryptedKey = networkEncryptedKey
		self.profileEncryptedKeys = profileEncryptedKeys
	}
}

public extension MobileKeyManager {
    func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData {
        let userRoot = try UserRootStore.load()
		let symmetricKey = SymmetricKey(size: .bits256)
		let sealed = try AES.GCM.seal(data, using: symmetricKey)
		let combined = sealed.combined ?? Data()
		let keyBytes = symmetricKey.withUnsafeBytes { Data($0) }

		var networkWrapped = Data()
		if let nid = networkId, !nid.isEmpty {
			let netPriv = try deriveNetworkAgreement(label: nid, userRoot: userRoot)
			let netPub = netPriv.publicKey
			networkWrapped = try ECIES.encrypt(data: keyBytes, recipientPublicKey: netPub)
		}

		var profileWraps: [String: Data] = [:]
		for pid in profileIds {
			let profPriv = try deriveProfileAgreement(label: pid, userRoot: userRoot)
			let profPub = profPriv.publicKey
			profileWraps[pid] = try ECIES.encrypt(data: keyBytes, recipientPublicKey: profPub)
		}

		return EnvelopeEncryptedData(
			encryptedData: combined,
			networkId: networkId,
			networkEncryptedKey: networkWrapped,
			profileEncryptedKeys: profileWraps
		)
	}

    func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data {
        let userRoot = try UserRootStore.load()
		guard let nid = envelopeData.networkId, !envelopeData.networkEncryptedKey.isEmpty else {
			throw NSError(domain: "Envelope", code: -1, userInfo: [NSLocalizedDescriptionKey: "No network wrap present"])
		}
		let netPriv = try deriveNetworkAgreement(label: nid, userRoot: userRoot)
		let keyBytes = try ECIES.decrypt(encrypted: envelopeData.networkEncryptedKey, recipientPrivateKey: netPriv)
		let symmetricKey = SymmetricKey(data: keyBytes)
		let box = try AES.GCM.SealedBox(combined: envelopeData.encryptedData)
		return try AES.GCM.open(box, using: symmetricKey)
	}

    func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId: String) throws -> Data {
        let userRoot = try UserRootStore.load()
		guard let wrapped = envelopeData.profileEncryptedKeys[profileId] else {
			throw NSError(domain: "Envelope", code: -1, userInfo: [NSLocalizedDescriptionKey: "No profile wrap for \(profileId)"])
		}
		let profPriv = try deriveProfileAgreement(label: profileId, userRoot: userRoot)
		let keyBytes = try ECIES.decrypt(encrypted: wrapped, recipientPrivateKey: profPriv)
		let symmetricKey = SymmetricKey(data: keyBytes)
		let box = try AES.GCM.SealedBox(combined: envelopeData.encryptedData)
		return try AES.GCM.open(box, using: symmetricKey)
	}
}


