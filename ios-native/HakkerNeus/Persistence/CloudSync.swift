import CloudKit
import os

/// Syncs saved stories, saved comments, read state and hidden stories between the user's devices,
/// through their private iCloud database with `CKSyncEngine`. The local database stays the source
/// of truth: changes are made there first and go out when there's a connection.
///
/// Each item is one record in a custom zone, named by its kind and HN ID ("SavedStory-123").
/// Unsaving deletes the record; visits are never deleted, and merge (the later opening and the
/// higher seen comment count win).
@MainActor
final class CloudSync {
    nonisolated static let containerIdentifier = "iCloud.se.lindskogen.hakkerneues"
    private nonisolated static let zoneID = CKRecordZone.ID(zoneName: "HakkerNeus")
    private static let log = Logger(subsystem: "se.lindskogen.hakkerneues", category: "CloudSync")

    /// A synced item.
    enum Item: Hashable {
        case savedStory(Int)
        case savedComment(Int)
        case visit(Int)
        case hiddenStory(Int)

        var recordType: CKRecord.RecordType {
            switch self {
            case .savedStory: "SavedStory"
            case .savedComment: "SavedComment"
            case .visit: "Visit"
            case .hiddenStory: "HiddenStory"
            }
        }

        var id: Int {
            switch self {
            case .savedStory(let id), .savedComment(let id), .visit(let id), .hiddenStory(let id): id
            }
        }

        var recordID: CKRecord.ID { CKRecord.ID(recordName: "\(recordType)-\(id)", zoneID: CloudSync.zoneID) }

        init?(recordID: CKRecord.ID) {
            guard recordID.zoneID == CloudSync.zoneID else { return nil }
            let parts = recordID.recordName.split(separator: "-")
            guard parts.count == 2, let id = Int(parts[1]) else { return nil }
            switch parts[0] {
            case "SavedStory": self = .savedStory(id)
            case "SavedComment": self = .savedComment(id)
            case "Visit": self = .visit(id)
            case "HiddenStory": self = .hiddenStory(id)
            default: return nil
            }
        }
    }

    private let database: Database
    private let savedStories: SavedStoriesStore
    private let savedComments: SavedCommentsStore
    private let visitedStories: VisitedStoriesStore
    private let hiddenStories: HiddenStoriesStore
    private let stateURL: URL
    private var engine: CKSyncEngine?

    init(
        database: Database,
        savedStories: SavedStoriesStore,
        savedComments: SavedCommentsStore,
        visitedStories: VisitedStoriesStore,
        hiddenStories: HiddenStoriesStore,
        stateURL: URL = .applicationSupportDirectory.appending(path: "CloudSync.state")
    ) throws {
        self.database = database
        self.savedStories = savedStories
        self.savedComments = savedComments
        self.visitedStories = visitedStories
        self.hiddenStories = hiddenStories
        self.stateURL = stateURL
        try Schema.migrate(database)
    }

    /// Starts syncing: sends what changed while the app wasn't running and fetches what changed elsewhere.
    func start() {
        guard engine == nil else { return }
        let state = (try? Data(contentsOf: stateURL)).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let container = CKContainer(identifier: Self.containerIdentifier)
        engine = CKSyncEngine(.init(database: container.privateCloudDatabase, stateSerialization: state, delegate: self))
        // The first time, everything already on this device goes up.
        if state == nil { sendEverything() }

        savedStories.onChange = { [unowned self] in changed(.savedStory($0)) }
        savedComments.onChange = { [unowned self] in changed(.savedComment($0)) }
        visitedStories.onChange = { [unowned self] in changed(.visit($0)) }
        hiddenStories.onChange = { [unowned self] in changed(.hiddenStory($0)) }
        syncNow()
    }

    /// Fetches changes from other devices and sends this device's now, e.g. when the app comes to
    /// the foreground. The engine also does both on its own schedule, but that can take minutes,
    /// and pushes announcing changes aren't guaranteed.
    func syncNow() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
            } catch {
                Self.log.info("Sync failed: \(error)")
            }
        }
    }

    #if DEBUG
    /// Saves a record of each type with every field set, in a scratch zone that's then deleted, so
    /// the Development schema has every field before it's deployed to Production (CloudKit only
    /// adds fields to the schema when a record first uses them). Run with `-SeedCloudKitSchema`.
    func seedSchema() async throws {
        let database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        let zone = CKRecordZone(zoneName: "SchemaSeed")
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        func record(_ type: String, _ fields: [String: CKRecordValue]) -> CKRecord {
            let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: type, zoneID: zone.zoneID))
            for (key, value) in fields { record[key] = value }
            return record
        }
        let now = Date() as NSDate
        let records = [
            record("SavedStory", [
                "title": "t" as NSString, "author": "a" as NSString, "url": "https://example.com" as NSString,
                "text": "t" as NSString, "score": 1 as NSNumber, "commentCount": 1 as NSNumber, "postedAt": now, "savedAt": now,
            ]),
            record("SavedComment", [
                "author": "a" as NSString, "text": "t" as NSString, "postedAt": now, "storyID": 1 as NSNumber,
                "storyTitle": "t" as NSString, "savedAt": now,
            ]),
            record("Visit", ["openedAt": now, "seenCommentCount": 1 as NSNumber]),
            record("HiddenStory", ["hiddenAt": now]),
        ]
        let (saved, _) = try await database.modifyRecords(saving: records, deleting: [])
        for (id, result) in saved { if case .failure(let error) = result { Self.log.error("Seeding \(id.recordName) failed: \(error)") } }
        _ = try await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
        Self.log.notice("Seeded the schema with \(records.count) record types")
    }
    #endif

    // MARK: Local changes

    private func exists(_ item: Item) -> Bool {
        switch item {
        case .savedStory(let id): savedStories.isSaved(id)
        case .savedComment(let id): savedComments.isSaved(id)
        case .visit(let id): visitedStories.isVisited(id)
        case .hiddenStory(let id): hiddenStories.isHidden(id)
        }
    }

    private func changed(_ item: Item) {
        guard let engine else { return }
        let id = item.recordID
        if exists(item) {
            engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        } else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
        }
    }

    private func sendEverything() {
        guard let engine else { return }
        let items: [Item] = savedStories.allEntries.map { .savedStory($0.story.id) }
            + savedComments.all.map { .savedComment($0.id) }
            + visitedStories.allIDs.map { .visit($0) }
            + hiddenStories.allIDs.map { .hiddenStory($0) }
        Self.log.info("Sending all \(items.count) items")
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        engine.state.add(pendingRecordZoneChanges: items.map { .saveRecord($0.recordID) })
    }

    /// The record to send for `id`, from the local copy; nil if it's gone since it was queued.
    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let item = Item(recordID: id) else { return nil }
        let record = cachedRecord(id) ?? CKRecord(recordType: item.recordType, recordID: id)
        switch item {
        case .savedStory(let id):
            guard let entry = savedStories.entry(id) else { return nil }
            let story = entry.story
            record["title"] = story.title
            record["author"] = story.author
            record["url"] = story.url?.absoluteString
            record["text"] = story.text
            record["score"] = story.score
            record["commentCount"] = story.commentCount
            record["postedAt"] = story.time
            record["savedAt"] = entry.savedAt
        case .savedComment(let id):
            guard let comment = savedComments.entry(id) else { return nil }
            record["author"] = comment.author
            record["text"] = comment.text
            record["postedAt"] = comment.time
            record["storyID"] = comment.storyID
            record["storyTitle"] = comment.storyTitle
            record["savedAt"] = comment.savedAt
        case .visit(let id):
            guard let visit = visitedStories.visit(id) else { return nil }
            record["openedAt"] = visit.openedAt
            record["seenCommentCount"] = visit.seenCommentCount
        case .hiddenStory(let id):
            guard hiddenStories.isHidden(id) else { return nil }
            if record["hiddenAt"] == nil { record["hiddenAt"] = Date() }
        }
        return record
    }

    // MARK: Remote changes

    private func apply(modified records: [CKRecord], deleted ids: [CKRecord.ID]) {
        var stories: [SavedStoriesStore.Entry] = [], comments: [SavedComment] = []
        var visits: [Int: VisitedStoriesStore.Visit] = [:], hidden: [Int] = []
        var unsavedStories: [Int] = [], unsavedComments: [Int] = [], unhidden: [Int] = []

        for record in records {
            guard let item = Item(recordID: record.recordID) else { continue }
            cache(record)
            switch item {
            case .savedStory(let id):
                guard let title = record["title"] as? String, let postedAt = record["postedAt"] as? Date,
                      let savedAt = record["savedAt"] as? Date
                else { continue }
                let story = Story(
                    id: id,
                    title: title,
                    author: record["author"] as? String,
                    url: (record["url"] as? String).flatMap(URL.init(string:)),
                    text: record["text"] as? String,
                    score: record["score"] as? Int ?? 0,
                    commentCount: record["commentCount"] as? Int ?? 0,
                    time: postedAt
                )
                stories.append(.init(story: story, savedAt: savedAt))
            case .savedComment(let id):
                guard let text = record["text"] as? String, let postedAt = record["postedAt"] as? Date,
                      let savedAt = record["savedAt"] as? Date
                else { continue }
                comments.append(SavedComment(
                    id: id, author: record["author"] as? String, text: text, time: postedAt,
                    storyID: record["storyID"] as? Int, storyTitle: record["storyTitle"] as? String, savedAt: savedAt
                ))
            case .visit(let id):
                guard let openedAt = record["openedAt"] as? Date else { continue }
                visits[id] = .init(openedAt: openedAt, seenCommentCount: record["seenCommentCount"] as? Int)
            case .hiddenStory(let id):
                hidden.append(id)
            }
        }
        for id in ids {
            uncache(id)
            switch Item(recordID: id) {
            case .savedStory(let id): unsavedStories.append(id)
            case .savedComment(let id): unsavedComments.append(id)
            case .hiddenStory(let id): unhidden.append(id)
            case .visit, nil: break
            }
        }

        do {
            try savedStories.applyRemote(saved: stories, removed: unsavedStories)
            try savedComments.applyRemote(saved: comments, removed: unsavedComments)
            try visitedStories.applyRemote(visits)
            hiddenStories.applyRemote(hidden: hidden, unhidden: unhidden)
        } catch {
            Self.log.error("Couldn't apply changes from iCloud: \(error)")
        }
    }

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let engine else { return }
        for record in event.savedRecords { cache(record) }
        for id in event.deletedRecordIDs { uncache(id) }
        for failure in event.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Changed on another device too: take theirs, merged with ours, and send again.
                guard let server = failure.error.serverRecord else { continue }
                apply(modified: [server], deleted: [])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .zoneNotFound:
                // The zone was deleted, e.g. from iCloud settings: make it again.
                uncache(id)
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .unknownItem:
                // Deleted on the server: send it as new.
                uncache(id)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .requestRateLimited:
                break // The engine retries these.
            default:
                Self.log.error("Couldn't send \(id.recordName): \(failure.error)")
            }
        }
    }

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            sendEverything()
        case .switchAccounts:
            // The saved stories stay on the device and go to the new account too.
            clearCache()
            sendEverything()
        case .signOut:
            clearCache()
        @unknown default:
            break
        }
    }

    // MARK: System fields

    private func cache(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        try? database.run(
            "INSERT OR REPLACE INTO cloud_records (name, system_fields) VALUES (?, ?)",
            [.text(record.recordID.recordName), .text(coder.encodedData.base64EncodedString())]
        )
    }

    private func cachedRecord(_ id: CKRecord.ID) -> CKRecord? {
        guard let row = try? database.query("SELECT system_fields FROM cloud_records WHERE name = ?", [.text(id.recordName)]).first,
              let data = row.string(0).flatMap({ Data(base64Encoded: $0) }),
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private func uncache(_ id: CKRecord.ID) {
        try? database.run("DELETE FROM cloud_records WHERE name = ?", [.text(id.recordName)])
    }

    private func clearCache() {
        try? database.run("DELETE FROM cloud_records")
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            do {
                try JSONEncoder().encode(update.stateSerialization).write(to: stateURL, options: .atomic)
            } catch {
                Self.log.error("Couldn't save the sync state: \(error)")
            }
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                // Deleted from iCloud settings: what's here stays, and goes up again.
                Self.log.info("The zone was deleted")
                clearCache()
                sendEverything()
            }
        case .fetchedRecordZoneChanges(let changes):
            Self.log.info("Fetched \(changes.modifications.count) changes, \(changes.deletions.count) deletions")
            apply(modified: changes.modifications.map(\.record), deleted: changes.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let sent):
            Self.log.info("Sent \(sent.savedRecords.count) records, \(sent.deletedRecordIDs.count) deletions, \(sent.failedRecordSaves.count) failed")
            handleSent(sent)
        case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.record(for: id)
        }
    }
}
