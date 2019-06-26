//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"
#import "ContactsManagerProtocol.h"
#import "SSKEnvironment.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger TSInfoMessageSchemaVersion = 1;

@interface TSInfoMessage ()

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger infoMessageSchemaVersion;

@end

#pragma mark -

@implementation TSInfoMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (self.infoMessageSchemaVersion < 1) {
        _read = YES;
    }

    _infoMessageSchemaVersion = TSInfoMessageSchemaVersion;

    if (self.isDynamicInteraction) {
        self.read = YES;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
{
    // MJK TODO - remove senderTimestamp
    self = [super initMessageWithTimestamp:timestamp
                                   inThread:thread
                                messageBody:nil
                              attachmentIds:@[]
                           expiresInSeconds:0
                            expireStartedAt:0
                              quotedMessage:nil
                               contactShare:nil
                                linkPreview:nil
                             messageSticker:nil
        perMessageExpirationDurationSeconds:0];

    if (!self) {
        return self;
    }

    _messageType = infoMessage;
    _infoMessageSchemaVersion = TSInfoMessageSchemaVersion;

    if (self.isDynamicInteraction) {
        self.read = YES;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
                    customMessage:(NSString *)customMessage
{
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _customMessage = customMessage;
    }
    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageType:(TSInfoMessageType)infoMessage
          unregisteredRecipientId:(NSString *)unregisteredRecipientId
{
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _unregisteredRecipientId = unregisteredRecipientId;
    }
    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
perMessageExpirationDurationSeconds:(unsigned int)perMessageExpirationDurationSeconds
  perMessageExpirationHasExpired:(BOOL)perMessageExpirationHasExpired
       perMessageExpireStartedAt:(uint64_t)perMessageExpireStartedAt
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                   schemaVersion:(NSUInteger)schemaVersion
                   customMessage:(nullable NSString *)customMessage
        infoMessageSchemaVersion:(NSUInteger)infoMessageSchemaVersion
                     messageType:(TSInfoMessageType)messageType
                            read:(BOOL)read
         unregisteredRecipientId:(nullable NSString *)unregisteredRecipientId
{
    self = [super initWithUniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId
                     attachmentIds:attachmentIds
                              body:body
                      contactShare:contactShare
                   expireStartedAt:expireStartedAt
                         expiresAt:expiresAt
                  expiresInSeconds:expiresInSeconds
                       linkPreview:linkPreview
                    messageSticker:messageSticker
perMessageExpirationDurationSeconds:perMessageExpirationDurationSeconds
    perMessageExpirationHasExpired:perMessageExpirationHasExpired
         perMessageExpireStartedAt:perMessageExpireStartedAt
                     quotedMessage:quotedMessage
                     schemaVersion:schemaVersion];

    if (!self) {
        return self;
    }

    _customMessage = customMessage;
    _infoMessageSchemaVersion = infoMessageSchemaVersion;
    _messageType = messageType;
    _read = read;
    _unregisteredRecipientId = unregisteredRecipientId;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

#pragma mark - Dependencies

- (id<ContactsManagerProtocol>)contactsManager
{
    return SSKEnvironment.shared.contactsManager;
}

#pragma mark -

+ (instancetype)userNotRegisteredMessageInThread:(TSThread *)thread recipientId:(NSString *)recipientId
{
    OWSAssertDebug(thread);
    OWSAssertDebug(recipientId);

    // MJK TODO - remove senderTimestamp
    return [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                  inThread:thread
                               messageType:TSInfoMessageUserNotRegistered
                   unregisteredRecipientId:recipientId];
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Info;
}

- (NSString *)previewTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    switch (_messageType) {
        case TSInfoMessageTypeSessionDidEnd:
            return NSLocalizedString(@"SECURE_SESSION_RESET", nil);
        case TSInfoMessageTypeUnsupportedMessage:
            return NSLocalizedString(@"UNSUPPORTED_ATTACHMENT", nil);
        case TSInfoMessageUserNotRegistered:
            if (self.unregisteredRecipientId.length > 0) {
                NSString *recipientName;
                if (transaction.transitional_yapReadTransaction != nil) {
                    recipientName = [self.contactsManager
                        displayNameForAddress:self.unregisteredRecipientId.transitional_signalServiceAddress
                                  transaction:transaction.transitional_yapReadTransaction];
                }
                return [NSString stringWithFormat:NSLocalizedString(@"ERROR_UNREGISTERED_USER_FORMAT",
                                                      @"Format string for 'unregistered user' error. Embeds {{the "
                                                      @"unregistered user's name or signal id}}."),
                                 recipientName];
            } else {
                return NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_INSECURE", nil);
            }
        case TSInfoMessageTypeGroupQuit:
            return NSLocalizedString(@"GROUP_YOU_LEFT", nil);
        case TSInfoMessageTypeGroupUpdate:
            return _customMessage != nil ? _customMessage : NSLocalizedString(@"GROUP_UPDATED", nil);
        case TSInfoMessageAddToContactsOffer:
            return NSLocalizedString(@"ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.");
        case TSInfoMessageVerificationStateChange:
            return NSLocalizedString(@"VERIFICATION_STATE_CHANGE_GENERIC",
                @"Generic message indicating that verification state changed for a given user.");
        case TSInfoMessageAddUserToProfileWhitelistOffer:
            return NSLocalizedString(@"ADD_USER_TO_PROFILE_WHITELIST_OFFER",
                @"Message shown in conversation view that offers to share your profile with a user.");
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
            return NSLocalizedString(@"ADD_GROUP_TO_PROFILE_WHITELIST_OFFER",
                @"Message shown in conversation view that offers to share your profile with a group.");
        case TSInfoMessageTypeDisappearingMessagesUpdate:
            break;
        case TSInfoMessageUnknownProtocolVersion:
            break;
        case TSInfoMessageUserJoinedSignal: {
            NSString *recipientName;
            if (transaction.transitional_yapReadTransaction != nil) {
                NSString *contactId = [TSContactThread contactIdFromThreadId:self.uniqueThreadId];
                recipientName =
                    [self.contactsManager displayNameForAddress:contactId.transitional_signalServiceAddress
                                                    transaction:transaction.transitional_yapReadTransaction];
            }
            NSString *format = NSLocalizedString(@"INFO_MESSAGE_USER_JOINED_SIGNAL_BODY_FORMAT",
                @"Shown in inbox and conversation when a user joins Signal, embeds the new user's {{contact name}}");
            return [NSString stringWithFormat:format, recipientName];
        }
    }

    OWSFailDebug(@"Unknown info message type");
    return @"";
}

#pragma mark - OWSReadTracking

- (BOOL)shouldAffectUnreadCounts
{
    switch (self.messageType) {
        case TSInfoMessageTypeSessionDidEnd:
        case TSInfoMessageUserNotRegistered:
        case TSInfoMessageTypeUnsupportedMessage:
        case TSInfoMessageTypeGroupUpdate:
        case TSInfoMessageTypeGroupQuit:
        case TSInfoMessageTypeDisappearingMessagesUpdate:
        case TSInfoMessageAddToContactsOffer:
        case TSInfoMessageVerificationStateChange:
        case TSInfoMessageAddUserToProfileWhitelistOffer:
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
        case TSInfoMessageUnknownProtocolVersion:
            return NO;
        case TSInfoMessageUserJoinedSignal:
            // In the home view, we want conversations with an unread "new user" notification to
            // be badged and bolded, like they received a message.
            return YES;
    }
}

- (uint64_t)expireStartedAt
{
    return 0;
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
              sendReadReceipt:(BOOL)sendReadReceipt
                  transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.read) {
        return;
    }

    OWSLogDebug(@"marking as read uniqueId: %@ which has timestamp: %llu", self.uniqueId, self.timestamp);

    [self anyUpdateWithTransaction:transaction
                             block:^(TSInteraction *interaction) {
                                 if (![interaction isKindOfClass:[TSInfoMessage class]]) {
                                     OWSFailDebug(@"Object has unexpected type: %@", [interaction class]);
                                     return;
                                 }
                                 TSInfoMessage *message = (TSInfoMessage *)interaction;
                                 message.read = YES;
                             }];

    // Ignore sendReadReceipt, it doesn't apply to info messages.
}

@end

NS_ASSUME_NONNULL_END
