//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol CVLoadCoordinatorDelegate: UIScrollViewDelegate {
    var viewState: CVViewState { get }

    func willUpdateWithNewRenderState(_ renderState: CVRenderState) -> CVUpdateToken

    func updateWithNewRenderState(update: CVUpdate,
                                  scrollAction: CVScrollAction,
                                  updateToken: CVUpdateToken)

    func updateScrollingContent()

    func chatColorDidChange()

    var isScrolledToBottom: Bool { get }

    var isScrollNearTopOfLoadWindow: Bool { get }

    var isScrollNearBottomOfLoadWindow: Bool { get }

    var isLayoutApplyingUpdate: Bool { get }

    var areCellsAnimating: Bool { get }

    var conversationViewController: ConversationViewController? { get }
}

// MARK: -

// This token lets CVC capture state from "before" a load
// lands that can be used when landing that load.
struct CVUpdateToken {
    let isScrolledToBottom: Bool
    let lastMessageForInboxSortId: UInt64?
    let scrollContinuityToken: CVScrollContinuityToken
    let lastKnownDistanceFromBottom: CGFloat?
}

public class CVLoadCoordinator: NSObject {

    private weak var delegate: CVLoadCoordinatorDelegate?
    private weak var componentDelegate: CVComponentDelegate?

    private let viewState: CVViewState
    private var mediaCache: CVMediaCache { viewState.mediaCache }

    private let threadUniqueId: String

    private var conversationStyle: ConversationStyle

    var renderState: CVRenderState

    // CVC is perf-sensitive during its initial load and
    // presentation. We can use this flag to skip any expensive
    // work before the first load is complete.
    public var hasRenderState: Bool {
        !renderState.isEmptyInitialState
    }

    public var shouldHideCollectionViewContent = true {
        didSet {
            owsAssertDebug(!shouldHideCollectionViewContent)
        }
    }

    private var hasClearedUnreadMessagesIndicator = false

    private let messageMapping: CVMessageMapping

    // TODO: Remove. This model will get stale.
    private let thread: TSThread

    private var loadDidLandResolver: Resolver<Void>?

    required init(viewState: CVViewState) {
        self.viewState = viewState
        let threadViewModel = viewState.threadViewModel
        self.threadUniqueId = threadViewModel.threadRecord.uniqueId
        self.thread = threadViewModel.threadRecord
        self.conversationStyle = viewState.conversationStyle

        let viewStateSnapshot = CVViewStateSnapshot.snapshot(viewState: viewState,
                                                             typingIndicatorsSender: nil,
                                                             hasClearedUnreadMessagesIndicator: hasClearedUnreadMessagesIndicator, wasShowingSelectionUI: false)
        self.renderState = CVRenderState.defaultRenderState(threadViewModel: threadViewModel,
                                                            viewStateSnapshot: viewStateSnapshot)

        self.messageMapping = CVMessageMapping(thread: threadViewModel.threadRecord)

        super.init()
    }

    func configure(delegate: CVLoadCoordinatorDelegate,
                   componentDelegate: CVComponentDelegate,
                   focusMessageIdOnOpen: String?) {
        self.delegate = delegate
        self.componentDelegate = componentDelegate

        Self.databaseStorage.appendDatabaseChangeDelegate(self)

        // Kick off async load.
        loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen)
    }

    // MARK: -

    public func viewDidLoad() {
        addNotificationListeners()
    }

    // MARK: - Notifications

    private func addNotificationListeners() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(typingIndicatorStateDidChange),
                                               name: TypingIndicatorsImpl.typingIndicatorStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange),
                                               name: .profileWhitelistDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: .blockListDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localProfileDidChange),
                                               name: .localProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(skipContactAvatarBlurDidChange(notification:)),
                                               name: OWSContactsManager.skipContactAvatarBlurDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(skipGroupAvatarBlurDidChange(notification:)),
                                               name: OWSContactsManager.skipGroupAvatarBlurDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(conversationChatColorSettingDidChange),
                                               name: ChatColors.conversationChatColorSettingDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(customChatColorsDidChange),
                                               name: ChatColors.customChatColorsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(autoChatColorsDidChange),
                                               name: ChatColors.autoChatColorsDidChange,
                                               object: nil)
        callService.addObserver(observer: self, syncStateImmediately: false)
    }

    @objc
    func applicationDidEnterBackground() {
         resetClearedUnreadMessagesIndicator()
    }

    @objc
    func typingIndicatorStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let notificationThreadId = notification.object as? String else {
            return
        }
        guard notificationThreadId == thread.uniqueId else {
            return
        }

        enqueueReload()
    }

    @objc
    func profileWhitelistDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func blockListDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func localProfileDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        if let contactThread = thread as? TSContactThread {
            guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
                  address.isValid else {
                owsFailDebug("Missing or invalid address.")
                return
            }
            if contactThread.contactAddress == address {
                enqueueReloadWithoutCaches()
            }
        } else {
            // TODO: In groups, we could reload if any group member's profile changed.
            //       Ideally we would only reload cells that use that member's profile state.            
        }
    }

    @objc
    func skipContactAvatarBlurDidChange(notification: Notification) {
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress else {
            owsFailDebug("Missing address.")
            return
        }
        if let contactThread = thread as? TSContactThread {
            if contactThread.contactAddress == address {
                enqueueReloadWithoutCaches()
            }
        } else if let groupThread = thread as? TSGroupThread {
            if groupThread.groupMembership.allMembersOfAnyKind.contains(address) {
                enqueueReloadWithoutCaches()
            }
        } else {
            owsFailDebug("Invalid thread.")
        }
    }

    @objc
    func skipGroupAvatarBlurDidChange(notification: Notification) {
        guard let groupUniqueId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        guard let groupThread = thread as? TSGroupThread,
              groupThread.uniqueId == groupUniqueId else {
            return
        }
        enqueueReloadWithoutCaches()
    }

    @objc
    private func conversationChatColorSettingDidChange(_ notification: NSNotification) {
        guard let threadUniqueId = notification.userInfo?[ChatColors.conversationChatColorSettingDidChangeThreadUniqueIdKey] as? String else {
            owsFailDebug("Missing threadUniqueId.")
            return
        }
        guard threadUniqueId == thread.uniqueId else {
            return
        }
        delegate?.chatColorDidChange()
    }

    @objc
    private func customChatColorsDidChange(_ notification: NSNotification) {
        delegate?.chatColorDidChange()
    }

    @objc
    private func autoChatColorsDidChange(_ notification: NSNotification) {
        delegate?.chatColorDidChange()
    }

    func appendUnsavedOutgoingTextMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()
        // TODO:
        //        // Because the message isn't yet saved, we don't have sufficient information to build
        //        // in-memory placeholder for message types more complex than plain text.
        //        OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
        //        OWSAssertDebug(outgoingMessage.contactShare == nil);
        //
        //        NSMutableArray<TSOutgoingMessage *> *unsavedOutgoingMessages = [self.unsavedOutgoingMessages mutableCopy];
        //        [unsavedOutgoingMessages addObject:outgoingMessage];
        //        self.unsavedOutgoingMessages = unsavedOutgoingMessages;
        //
        //        [self updateForTransientItems];
    }

    // MARK: -

    public var canLoadOlderItems: Bool {
        renderState.canLoadOlderItems
    }

    public var canLoadNewerItems: Bool {
        renderState.canLoadNewerItems
    }

    // MARK: - Load Requests

    // This property should only be accessed on the main thread.
    private var loadRequestBuilder = CVLoadRequest.Builder()

    // For thread safety, we can only have one load
    // in flight at a time. Entities like the MessageMapping
    // are not thread-safe.
    private let isLoading = AtomicBool(false)
    public var hasLoadInFlight: Bool { isLoading.get() }

    private let autoLoadMoreThreshold: TimeInterval = 2 * kSecondInterval

    private var lastLoadOlderDate: Date?
    public var didLoadOlderRecently: Bool {
        AssertIsOnMainThread()

        guard let lastLoadOlderDate = lastLoadOlderDate else {
            return false
        }
        return abs(lastLoadOlderDate.timeIntervalSinceNow) < autoLoadMoreThreshold
    }

    private var lastLoadNewerDate: Date?
    public var didLoadNewerRecently: Bool {
        AssertIsOnMainThread()

        guard let lastLoadNewerDate = lastLoadNewerDate else {
            return false
        }
        return abs(lastLoadNewerDate.timeIntervalSinceNow) < autoLoadMoreThreshold
    }
    private func loadInitialMapping(focusMessageIdOnOpen: String?) {
        owsAssertDebug(renderState.isEmptyInitialState)
        loadRequestBuilder.loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen)
        loadIfNecessary()
    }

    public func loadOlderItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadOlderItems()
        loadIfNecessary()
    }

    public func loadNewerItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadNewerItems()
        loadIfNecessary()
    }

    public func loadAndScrollToNewestItems(isAnimated: Bool) {
        loadRequestBuilder.loadAndScrollToNewestItems(isAnimated: isAnimated)
        loadIfNecessary()
    }

    public func enqueueReload() {
        loadRequestBuilder.reload()
        loadIfNecessary()
    }

    public func enqueueReload(scrollAction: CVScrollAction) {
        loadRequestBuilder.reload(scrollAction: scrollAction)
        loadIfNecessary()
    }

    public func enqueueReload(updatedInteractionIds: Set<String>,
                              deletedInteractionIds: Set<String>) {
        AssertIsOnMainThread()

        loadRequestBuilder.reload(updatedInteractionIds: updatedInteractionIds,
                                  deletedInteractionIds: deletedInteractionIds)
        loadIfNecessary()
    }

    public func enqueueLoadAndScrollToInteraction(interactionId: String,
                                                  onScreenPercentage: CGFloat,
                                                  alignment: ScrollAlignment,
                                                  isAnimated: Bool) {
        AssertIsOnMainThread()

        loadRequestBuilder.loadAndScrollToInteraction(interactionId: interactionId,
                                                      onScreenPercentage: onScreenPercentage,
                                                      alignment: alignment,
                                                      isAnimated: isAnimated)
        loadIfNecessary()
    }

    public func enqueueReloadWithoutCaches() {
        AssertIsOnMainThread()

        loadRequestBuilder.reloadWithoutCaches()
        loadIfNecessary()
    }

    public func enqueueReload(canReuseInteractionModels: Bool,
                              canReuseComponentStates: Bool) {
        AssertIsOnMainThread()

        loadRequestBuilder.reload(canReuseInteractionModels: canReuseInteractionModels,
                                  canReuseComponentStates: canReuseComponentStates)
        loadIfNecessary()
    }

    // MARK: - Conversation Style

    public func updateConversationStyle(_ conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        self.conversationStyle = conversationStyle

        // We need to kick off a reload cycle if conversationStyle changes.
        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    // MARK: - Unread Indicator

    func clearUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        // Once we've cleared the unread messages indicator,
        // make sure we don't show it again.
        hasClearedUnreadMessagesIndicator = true

        guard nil != messageMapping.oldestUnreadInteraction else {
            return
        }

        loadRequestBuilder.clearOldestUnreadInteraction()
        loadIfNecessary()
    }

    // MARK: -

    func resetClearedUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        hasClearedUnreadMessagesIndicator = false

        loadRequestBuilder.clearOldestUnreadInteraction()
        loadIfNecessary()
    }

    // MARK: -

    #if TESTABLE_BUILD
    public let blockLoads = AtomicBool(false)
    #endif

    private func loadIfNecessary() {
        AssertIsOnMainThread()

        let conversationStyle = self.conversationStyle
        guard conversationStyle.viewWidth > 0 else {
            Logger.info("viewWidth not yet set.")
            return
        }
        guard let loadRequest = loadRequestBuilder.build() else {
            // No load is needed.
            return
        }
        #if TESTABLE_BUILD
        guard !blockLoads.get() else {
            return
        }
        #endif
        guard isLoading.tryToSetFlag() else {
            Logger.verbose("Ignoring; already loading.")
            return
        }

        loadRequestBuilder = CVLoadRequest.Builder()

        load(loadRequest: loadRequest,
             conversationStyle: conversationStyle)
    }

    private func load(loadRequest: CVLoadRequest, conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()
        // We should do an "initial" load IFF this is our first load.
        owsAssertDebug(loadRequest.isInitialLoad == renderState.isEmptyInitialState)

        guard isLoading.get() else {
            owsFailDebug("isLoading not set.")
            return
        }
        let prevRenderState = renderState

        if loadRequest.loadType == .loadOlder {
            lastLoadOlderDate = Date()
        } else if loadRequest.loadType == .loadNewer {
            lastLoadNewerDate = Date()
        }

        let typingIndicatorsSender = typingIndicatorsImpl.typingAddress(forThread: thread)
        let viewStateSnapshot = CVViewStateSnapshot.snapshot(viewState: viewState,
                                                             typingIndicatorsSender: typingIndicatorsSender,
                                                             hasClearedUnreadMessagesIndicator: hasClearedUnreadMessagesIndicator,
                                                             wasShowingSelectionUI: prevRenderState.viewStateSnapshot.isShowingSelectionUI)
        let loader = CVLoader(threadUniqueId: threadUniqueId,
                              loadRequest: loadRequest,
                              viewStateSnapshot: viewStateSnapshot,
                              prevRenderState: prevRenderState,
                              messageMapping: messageMapping)

        firstly { () -> Promise<CVUpdate> in
            loader.loadPromise()
        }.then { [weak self] (update: CVUpdate) -> Promise<Void> in
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            guard let delegate = self.delegate else {
                throw OWSGenericError("Missing delegate.")
            }
            return self.loadLandWhenSafePromise(update: update, delegate: delegate)
        }.done { [weak self] () -> Void in
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            guard self.isLoading.tryToClearFlag() else {
                owsFailDebug("Could not clear isLoading flag.")
                return
            }
            // Initiate new load if necessary.
            self.loadIfNecessary()
        }.catch(on: CVUtils.workQueue(isInitialLoad: loadRequest.isInitialLoad)) { [weak self] (error) in
            guard let self = self else {
                return
            }
            owsFailDebug("Error: \(error)")
            guard self.isLoading.tryToClearFlag() else {
                owsFailDebug("Could not clear isLoading flag.")
                return
            }
            // Initiate new load if necessary.
            self.loadIfNecessary()
        }
    }

    // MARK: - Safe Landing

    // Lands the load when its safe, blocking on scrolling.
    private func loadLandWhenSafePromise(update: CVUpdate,
                                         delegate: CVLoadCoordinatorDelegate) -> Promise<Void> {
        AssertIsOnMainThread()

        let (loadPromise, loadResolver) = Promise<Void>.pending()

        func canLandLoad() -> Bool {
            AssertIsOnMainThread()

            // Allow multi selection animation load to land, even if keyboard is animating
            if let lastKeyboardAnimationDate = viewState.lastKeyboardAnimationDate,
               lastKeyboardAnimationDate.isAfterNow, viewState.selectionAnimationState != .willAnimate {
                return false
            }

            guard viewState.selectionAnimationState != .animating  else { return false }

            let result = !delegate.isLayoutApplyingUpdate && !delegate.areCellsAnimating
            return result
        }

        func tryToResolve() {
            guard canLandLoad() else {
                // TODO: async() or asyncAfter()?
                if !DebugFlags.reduceLogChatter {
                    Logger.verbose("Waiting to land load.")
                }
                // We wait in a pretty tight loop to ensure loads land in a timely way.
                //
                // DispatchQueue.asyncAfter() will take longer to perform
                // its block than DispatchQueue.async() if the CPU is under
                // heavy load. That's desirable in this case.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    tryToResolve()
                }
                return
            }

            let renderState = update.renderState
            let updateToken = delegate.willUpdateWithNewRenderState(renderState)

            self.renderState = renderState

            let (loadDidLandPromise, loadDidLandResolver) = Promise<Void>.pending()
            self.loadDidLandResolver = loadDidLandResolver

            let loadRequest = update.loadRequest
            delegate.updateWithNewRenderState(update: update,
                                              scrollAction: loadRequest.scrollAction,
                                              updateToken: updateToken)

            firstly { () -> Promise<Void> in
                // We've started the process of landing the load,
                // but its completion may be async.
                //
                // Block on load land completion.
                loadDidLandPromise
            }.done(on: CVUtils.landingQueue) {
                loadResolver.fulfill(())
            }.catch(on: CVUtils.landingQueue) { error in
                loadResolver.reject(error)
            }
        }

        tryToResolve()

        return loadPromise
    }

    // -

    public func loadDidLand() {
        AssertIsOnMainThread()
        guard let loadDidLandResolver = loadDidLandResolver else {
            owsFailDebug("Missing loadDidLandResolver.")
            return
        }
        loadDidLandResolver.fulfill(())
        self.loadDidLandResolver = nil
    }
}

// MARK: -

extension CVLoadCoordinator: DatabaseChangeDelegate {

    public func databaseChangesWillUpdate() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
    }

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.threadUniqueIds.contains(threadUniqueId) else {
            return
        }
        enqueueReload(updatedInteractionIds: databaseChanges.interactionUniqueIds,
                      deletedInteractionIds: databaseChanges.interactionDeletedUniqueIds)
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }
}

// MARK: -

@objc
extension CVLoadCoordinator: UICollectionViewDataSource {

    public static let messageSection: Int = 0

    public var renderItems: [CVRenderItem] {
        AssertIsOnMainThread()

        return shouldHideCollectionViewContent ? [] : renderState.items
    }

    public var renderStateId: UInt {
        return shouldHideCollectionViewContent ? CVRenderState.renderStateId_unknown : renderState.renderStateId
    }

    var allIndexPaths: [IndexPath] {
        AssertIsOnMainThread()

        return renderState.allIndexPaths
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        owsAssertDebug(sectionIdx == Self.messageSection)

        return renderItems.count
    }

    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        owsAssertDebug(indexPath.section == Self.messageSection)

        guard let componentDelegate = self.componentDelegate else {
            owsFailDebug("Missing componentDelegate.")
            return UICollectionViewCell()
        }
        guard let renderItem = renderItems[safe: indexPath.row] else {
            owsFailDebug("Missing renderItem.")
            return UICollectionViewCell()
        }
        let cellReuseIdentifier = renderItem.cellReuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier,
                                                            for: indexPath) as? CVCell else {
            owsFailDebug("Missing cell.")
            return UICollectionViewCell()
        }
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return UICollectionViewCell()
        }
        let cellSelection = delegate.viewState.cellSelection
        let messageSwipeActionState = delegate.viewState.messageSwipeActionState
        cell.configure(renderItem: renderItem,
                       componentDelegate: componentDelegate,
                       cellSelection: cellSelection,
                       messageSwipeActionState: messageSwipeActionState)
        return cell

        //        // This must happen after load for display, since the tap
        //        // gesture doesn't get added to a view until this point.
        //        if ([cell isKindOfClass:[OWSMessageCell class]]) {
        //            OWSMessageCell *messageCell = (OWSMessageCell *)cell;
        //            [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.messageViewTapGestureRecognizer];
        //            [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.contentViewTapGestureRecognizer];
        //
        //            [messageCell.messageViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];
        //            [messageCell.contentViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];
        //        }
        //
        //        #ifdef DEBUG
        //        // TODO: Confirm with nancy if this will work.
        //        NSString *cellName = [NSString stringWithFormat:@"interaction.%@", NSUUID.UUID.UUIDString];
        //        if (viewItem.hasBodyText && viewItem.displayableBodyText.displayAttributedText.length > 0) {
        //            NSString *textForId =
        //                [viewItem.displayableBodyText.displayAttributedText.string stringByReplacingOccurrencesOfString:@" "
        //                    withString:@"_"];
        //            cellName = [NSString stringWithFormat:@"message.text.%@", textForId];
        //        } else if (viewItem.stickerInfo) {
        //            cellName = [NSString stringWithFormat:@"message.sticker.%@", [viewItem.stickerInfo asKey]];
        //        }
        //        cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);
        // #endif
        //
        // return cell;
    }

    public func collectionView(_ collectionView: UICollectionView,
                               viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader ||
            kind == UICollectionView.elementKindSectionFooter else {
            owsFailDebug("unexpected supplementaryElement: \(kind)")
            return UICollectionReusableView()
        }
        guard let loadMoreView =
                collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier,
                                                                for: indexPath) as? LoadMoreMessagesView else {
            owsFailDebug("Couldn't load supplementary view: \(kind)")
            return UICollectionReusableView()
        }
        loadMoreView.configureForDisplay()
        return loadMoreView
    }

    public var indexPathOfUnreadIndicator: IndexPath? {
        renderState.indexPathOfUnreadIndicator
    }

    public func indexPath(forInteractionUniqueId interactionUniqueId: String) -> IndexPath? {
        renderState.indexPath(forInteractionUniqueId: interactionUniqueId)
    }
}

// MARK: -

@objc
extension CVLoadCoordinator: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = true
        let delegate = self.delegate
        DispatchQueue.main.async {
            delegate?.updateScrollingContent()
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = false
        delegate?.updateScrollingContent()
    }
}

// MARK: -

@objc
extension CVLoadCoordinator: ConversationViewLayoutDelegate {

    public var layoutItems: [ConversationViewLayoutItem] {
        renderItems
    }

    public var showLoadOlderHeader: Bool {
        // We need to have at least one item to hang the supplementary view on.
        return canLoadOlderItems && !renderItems.isEmpty
    }

    public var showLoadNewerHeader: Bool {
        // We need to have at least one item to hang the supplementary view on.
        //
        // We could show both the "load older" and "load newer" items. If so we
        // need two items to hang the supplementary views on.
        let minItemCount = showLoadOlderHeader ? 2 : 1
        return canLoadNewerItems && renderItems.count >= minItemCount
    }

    public var layoutHeaderHeight: CGFloat {
        showLoadOlderHeader ? LoadMoreMessagesView.fixedHeight : 0
    }

    public var layoutFooterHeight: CGFloat {
        showLoadNewerHeader ? LoadMoreMessagesView.fixedHeight : 0
    }

    public var conversationViewController: ConversationViewController? {
        guard let delegate = self.delegate else {
            owsFailDebug("Missing delegate.")
            return nil
        }
        return delegate.conversationViewController
    }
}

// MARK: -

extension CVLoadCoordinator: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScroll?(scrollView)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        delegate?.scrollViewShouldScrollToTop?(scrollView) ?? false
    }

    public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScrollToTop?(scrollView)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }
}

// MARK: -

extension CVLoadCoordinator: CallServiceObserver {
    public func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        guard thread.isGroupV2Thread else {
            return
        }
        guard oldValue?.thread.uniqueId == thread.uniqueId ||
                newValue?.thread.uniqueId == thread.uniqueId else {
            return
        }
        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }
}
