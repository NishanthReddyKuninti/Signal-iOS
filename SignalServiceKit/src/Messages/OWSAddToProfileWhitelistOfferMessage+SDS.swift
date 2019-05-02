//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSAddToProfileWhitelistOfferMessageSerializer: SDSSerializer {

    private let model: OWSAddToProfileWhitelistOfferMessage
    public required init(model: OWSAddToProfileWhitelistOfferMessage) {
        self.model = model
    }

    public func serializableColumnTableMetadata() -> SDSTableMetadata {
        return TSInteractionSerializer.table
    }

    public func insertColumnNames() -> [String] {
        // When we insert a new row, we include the following columns:
        //
        // * "record type"
        // * "unique id"
        // * ...all columns that we set when updating.
        return [
            TSInteractionSerializer.recordTypeColumn.columnName,
            uniqueIdColumnName()
            ] + updateColumnNames()

    }

    public func insertColumnValues() -> [DatabaseValueConvertible] {
        let result: [DatabaseValueConvertible] = [
            SDSRecordType.addToProfileWhitelistOfferMessage.rawValue
            ] + [uniqueIdColumnValue()] + updateColumnValues()
        if OWSIsDebugBuild() {
            if result.count != insertColumnNames().count {
                owsFailDebug("Update mismatch: \(result.count) != \(insertColumnNames().count)")
            }
        }
        return result
    }

    public func updateColumnNames() -> [String] {
        return [
            TSInteractionSerializer.receivedAtTimestampColumn,
            TSInteractionSerializer.timestampColumn,
            TSInteractionSerializer.uniqueThreadIdColumn,
            TSInteractionSerializer.attachmentIdsColumn,
            TSInteractionSerializer.bodyColumn,
            TSInteractionSerializer.contactShareColumn,
            TSInteractionSerializer.expireStartedAtColumn,
            TSInteractionSerializer.expiresAtColumn,
            TSInteractionSerializer.expiresInSecondsColumn,
            TSInteractionSerializer.linkPreviewColumn,
            TSInteractionSerializer.messageStickerColumn,
            TSInteractionSerializer.quotedMessageColumn,
            TSInteractionSerializer.schemaVersionColumn,
            TSInteractionSerializer.customMessageColumn,
            TSInteractionSerializer.infoMessageSchemaVersionColumn,
            TSInteractionSerializer.messageTypeColumn,
            TSInteractionSerializer.readColumn,
            TSInteractionSerializer.unregisteredRecipientIdColumn,
            TSInteractionSerializer.contactIdColumn
            ].map { $0.columnName }
    }

    public func updateColumnValues() -> [DatabaseValueConvertible] {
        let result: [DatabaseValueConvertible] = [
            self.model.receivedAtTimestamp,
            self.model.timestamp,
            self.model.uniqueThreadId,
            SDSDeserializer.archive(self.model.attachmentIds) ?? DatabaseValue.null,
            self.model.body ?? DatabaseValue.null,
            SDSDeserializer.archive(self.model.contactShare) ?? DatabaseValue.null,
            self.model.expireStartedAt,
            self.model.expiresAt,
            self.model.expiresInSeconds,
            SDSDeserializer.archive(self.model.linkPreview) ?? DatabaseValue.null,
            SDSDeserializer.archive(self.model.messageSticker) ?? DatabaseValue.null,
            SDSDeserializer.archive(self.model.quotedMessage) ?? DatabaseValue.null,
            self.model.schemaVersion,
            self.model.customMessage ?? DatabaseValue.null,
            self.model.infoMessageSchemaVersion,
            self.model.messageType.rawValue,
            self.model.wasRead,
            self.model.unregisteredRecipientId ?? DatabaseValue.null,
            self.model.contactId

        ]
        if OWSIsDebugBuild() {
            if result.count != updateColumnNames().count {
                owsFailDebug("Update mismatch: \(result.count) != \(updateColumnNames().count)")
            }
        }
        return result
    }

    public func uniqueIdColumnName() -> String {
        return TSInteractionSerializer.uniqueIdColumn.columnName
    }

    // TODO: uniqueId is currently an optional on our models.
    //       We should probably make the return type here String?
    public func uniqueIdColumnValue() -> DatabaseValueConvertible {
        // FIXME remove force unwrap
        return model.uniqueId!
    }
}
