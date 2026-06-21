import CloudKit
import Foundation

/// Best-effort writer for the public-database paid-status record (one per user, keyed by the
/// Sign-in-with-Apple user id) so the owner can see who's paying in the CloudKit Dashboard.
///
/// This is purely for owner visibility + cross-device hinting. Pro gating is ALWAYS decided by
/// StoreKit `currentEntitlements` (see `Store`). Every call here is non-blocking and failure-tolerant:
/// no iCloud account, no provisioned container, or any CloudKit error simply no-ops.
enum CloudSync {
    static let containerID = "iCloud.com.shimondeitel.spellchain"
    private static let kUserID = "spellchain.account.userID"

    static func recordPaidStatus(isPro: Bool, transactionID: String?) {
        let userID = UserDefaults.standard.string(forKey: kUserID) ?? ""
        guard !userID.isEmpty else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        Task.detached(priority: .background) {
            let db = CKContainer(identifier: containerID).publicCloudDatabase
            let recordID = CKRecord.ID(recordName: "paid-\(userID)")
            let record = (try? await db.record(for: recordID))
                ?? CKRecord(recordType: "PaidStatus", recordID: recordID)
            record["userID"] = userID as CKRecordValue
            record["isPro"] = (isPro ? 1 : 0) as CKRecordValue
            if let tx = transactionID { record["transactionID"] = tx as CKRecordValue }
            record["updatedAt"] = Date() as CKRecordValue
            _ = try? await db.save(record)
        }
    }

    /// Best-effort delete of the user's paid-status record (Account Deletion). No-ops without iCloud.
    static func deletePaidStatus(userID: String) {
        guard !userID.isEmpty else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else { return }
        Task.detached(priority: .background) {
            let db = CKContainer(identifier: containerID).publicCloudDatabase
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: "paid-\(userID)"))
        }
    }
}
