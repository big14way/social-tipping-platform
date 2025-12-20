;; tip-manager.clar
;; Social Tipping Platform with Chainhook-trackable events
;; Uses Clarity 4 features: stacks-block-time, restrict-assets?, to-ascii?
;; Emits print events for: tip-sent, tip-withdrawn, creator-registered, fee-collected

(define-constant CONTRACT_OWNER tx-sender)
(define-data-var contract-principal principal tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u22001))
(define-constant ERR_CREATOR_NOT_FOUND (err u22002))
(define-constant ERR_INVALID_AMOUNT (err u22003))
(define-constant ERR_INSUFFICIENT_BALANCE (err u22004))
(define-constant ERR_ALREADY_REGISTERED (err u22005))
(define-constant ERR_CONTENT_NOT_FOUND (err u22006))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u22007))
(define-constant ERR_CAMPAIGN_EXPIRED (err u22008))
(define-constant ERR_CAMPAIGN_NOT_ACTIVE (err u22009))
(define-constant ERR_INVALID_MULTIPLIER (err u22010))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u22011))
(define-constant ERR_SUBSCRIPTION_ACTIVE (err u22012))
(define-constant ERR_SUBSCRIPTION_CANCELLED (err u22013))
(define-constant ERR_PAYMENT_NOT_DUE (err u22014))

;; Protocol fee: 2.5% (250 basis points)
(define-constant PROTOCOL_FEE_BPS u250)

;; Minimum tip amount: 0.1 STX
(define-constant MIN_TIP_AMOUNT u100000)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var tip-counter uint u0)
(define-data-var creator-counter uint u0)
(define-data-var content-counter uint u0)
(define-data-var total-tips-volume uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var total-creators uint u0)
(define-data-var total-tippers uint u0)
(define-data-var campaign-counter uint u0)
(define-data-var total-boosted-tips uint u0)
(define-data-var total-boost-multiplier-applied uint u0)
(define-data-var subscription-counter uint u0)
(define-data-var total-active-subscriptions uint u0)
(define-data-var total-subscription-revenue uint u0)

;; ========================================
;; Data Maps
;; ========================================

;; Creator profiles
(define-map creators
    principal
    {
        creator-id: uint,
        username: (string-ascii 32),
        bio: (string-ascii 256),
        registered-at: uint,
        total-tips-received: uint,
        total-amount-received: uint,
        pending-balance: uint,
        supporter-count: uint,
        content-count: uint,
        verified: bool
    }
)

;; Content items (posts, videos, etc.)
(define-map content-items
    uint
    {
        creator: principal,
        content-type: (string-ascii 32),
        content-hash: (buff 32),
        title: (string-ascii 128),
        created-at: uint,
        tips-received: uint,
        total-amount: uint
    }
)

;; Individual tips
(define-map tips
    uint
    {
        tipper: principal,
        creator: principal,
        content-id: (optional uint),
        amount: uint,
        message: (optional (string-ascii 256)),
        timestamp: uint
    }
)

;; Tipper statistics
(define-map tipper-stats
    principal
    {
        total-tips-sent: uint,
        total-amount-tipped: uint,
        creators-supported: uint,
        first-tip: uint,
        last-tip: uint,
        fees-paid: uint
    }
)

;; Track unique tippers
(define-map registered-tippers principal bool)

;; Track supporters per creator
(define-map creator-supporters
    { creator: principal, supporter: principal }
    uint
)

;; Boost campaigns
(define-map boost-campaigns
    uint
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        multiplier: uint,
        start-time: uint,
        end-time: uint,
        active: bool,
        total-boosted-tips: uint,
        total-participants: uint,
        created-by: principal
    }
)

;; Track boosted tips
(define-map boosted-tips
    uint
    {
        campaign-id: uint,
        original-amount: uint,
        boosted-amount: uint,
        multiplier: uint
    }
)

;; Track booster leaderboard
(define-map booster-stats
    principal
    {
        total-boosted-tips: uint,
        total-boost-amount: uint,
        campaigns-participated: uint,
        highest-single-boost: uint
    }
)

;; Recurring subscriptions
(define-map subscriptions
    uint
    {
        subscriber: principal,
        creator: principal,
        amount: uint,
        interval-seconds: uint,
        created-at: uint,
        next-payment-due: uint,
        total-payments: uint,
        total-paid: uint,
        active: bool,
        cancelled-at: (optional uint)
    }
)

;; Track subscriptions per subscriber-creator pair
(define-map subscriber-to-creator
    { subscriber: principal, creator: principal }
    uint
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-current-time) stacks-block-time)

(define-read-only (get-creator (creator principal))
    (map-get? creators creator))

(define-read-only (get-content (content-id uint))
    (map-get? content-items content-id))

(define-read-only (get-tip (tip-id uint))
    (map-get? tips tip-id))

(define-read-only (get-tipper-stats (tipper principal))
    (map-get? tipper-stats tipper))

(define-read-only (is-registered-creator (creator principal))
    (is-some (map-get? creators creator)))

(define-read-only (calculate-fee (amount uint))
    (/ (* amount PROTOCOL_FEE_BPS) u10000))

(define-read-only (get-protocol-stats)
    {
        total-tips: (var-get tip-counter),
        total-creators: (var-get total-creators),
        total-tippers: (var-get total-tippers),
        total-volume: (var-get total-tips-volume),
        total-fees: (var-get total-fees-collected),
        total-content: (var-get content-counter),
        total-campaigns: (var-get campaign-counter),
        total-boosted-tips: (var-get total-boosted-tips),
        current-time: stacks-block-time
    })

(define-read-only (get-campaign (campaign-id uint))
    (map-get? boost-campaigns campaign-id))

(define-read-only (get-boosted-tip-info (tip-id uint))
    (map-get? boosted-tips tip-id))

(define-read-only (get-booster-stats (booster principal))
    (map-get? booster-stats booster))

(define-read-only (is-campaign-active (campaign-id uint))
    (match (map-get? boost-campaigns campaign-id)
        campaign (and (get active campaign)
                     (>= stacks-block-time (get start-time campaign))
                     (< stacks-block-time (get end-time campaign)))
        false))

(define-read-only (calculate-boosted-amount (amount uint) (campaign-id uint))
    (match (map-get? boost-campaigns campaign-id)
        campaign (if (is-campaign-active campaign-id)
                    (/ (* amount (get multiplier campaign)) u100)
                    u0)
        u0))

;; Generate creator info using to-ascii?
(define-read-only (generate-creator-info (creator principal))
    (match (map-get? creators creator)
        profile (let
            (
                (tips-str (unwrap-panic (to-ascii? (get total-tips-received profile))))
                (amount-str (unwrap-panic (to-ascii? (get total-amount-received profile))))
                (supporters-str (unwrap-panic (to-ascii? (get supporter-count profile))))
            )
            (concat 
                (concat (concat "@" (get username profile)) (concat " | Tips: " tips-str))
                (concat (concat " | Earned: " amount-str) (concat " | Supporters: " supporters-str))))
        "Creator not found"))

;; ========================================
;; Private Helper Functions
;; ========================================

(define-private (update-tipper-stats (tipper principal) (amount uint) (fee uint))
    (let
        (
            (current-stats (default-to 
                { total-tips-sent: u0, total-amount-tipped: u0, creators-supported: u0,
                  first-tip: stacks-block-time, last-tip: u0, fees-paid: u0 }
                (map-get? tipper-stats tipper)))
            (is-new-tipper (is-none (map-get? registered-tippers tipper)))
        )
        ;; Register new tipper
        (if is-new-tipper
            (begin
                (map-set registered-tippers tipper true)
                (var-set total-tippers (+ (var-get total-tippers) u1)))
            true)
        ;; Update stats
        (map-set tipper-stats tipper (merge current-stats {
            total-tips-sent: (+ (get total-tips-sent current-stats) u1),
            total-amount-tipped: (+ (get total-amount-tipped current-stats) amount),
            fees-paid: (+ (get fees-paid current-stats) fee),
            last-tip: stacks-block-time
        }))))

;; ========================================
;; Public Functions
;; ========================================

;; Register as creator
(define-public (register-creator (username (string-ascii 32)) (bio (string-ascii 256)))
    (let
        (
            (caller tx-sender)
            (creator-id (+ (var-get creator-counter) u1))
            (current-time stacks-block-time)
        )
        ;; Check not already registered
        (asserts! (not (is-registered-creator caller)) ERR_ALREADY_REGISTERED)
        
        ;; Create profile
        (map-set creators caller {
            creator-id: creator-id,
            username: username,
            bio: bio,
            registered-at: current-time,
            total-tips-received: u0,
            total-amount-received: u0,
            pending-balance: u0,
            supporter-count: u0,
            content-count: u0,
            verified: false
        })
        
        (var-set creator-counter creator-id)
        (var-set total-creators (+ (var-get total-creators) u1))
        
        ;; EMIT EVENT: creator-registered
        (print {
            event: "creator-registered",
            creator-id: creator-id,
            creator: caller,
            username: username,
            timestamp: current-time
        })
        
        (ok creator-id)))

;; Post content
(define-public (post-content (content-type (string-ascii 32)) (content-hash (buff 32)) (title (string-ascii 128)))
    (let
        (
            (caller tx-sender)
            (profile (unwrap! (map-get? creators caller) ERR_CREATOR_NOT_FOUND))
            (content-id (+ (var-get content-counter) u1))
            (current-time stacks-block-time)
        )
        ;; Create content
        (map-set content-items content-id {
            creator: caller,
            content-type: content-type,
            content-hash: content-hash,
            title: title,
            created-at: current-time,
            tips-received: u0,
            total-amount: u0
        })
        
        ;; Update creator content count
        (map-set creators caller (merge profile {
            content-count: (+ (get content-count profile) u1)
        }))
        
        (var-set content-counter content-id)
        
        ;; EMIT EVENT: content-posted
        (print {
            event: "content-posted",
            content-id: content-id,
            creator: caller,
            content-type: content-type,
            title: title,
            timestamp: current-time
        })
        
        (ok content-id)))

;; Send tip to creator
(define-public (send-tip 
    (creator principal) 
    (amount uint) 
    (content-id (optional uint))
    (message (optional (string-ascii 256))))
    (let
        (
            (caller tx-sender)
            (profile (unwrap! (map-get? creators creator) ERR_CREATOR_NOT_FOUND))
            (tip-id (+ (var-get tip-counter) u1))
            (current-time stacks-block-time)
            (fee (calculate-fee amount))
            (creator-amount (- amount fee))
            (existing-support (default-to u0 (map-get? creator-supporters { creator: creator, supporter: caller })))
        )
        ;; Validations
        (asserts! (>= amount MIN_TIP_AMOUNT) ERR_INVALID_AMOUNT)
        
        ;; Transfer tip
        (try! (stx-transfer? amount caller (var-get contract-principal)))

        ;; Transfer fee to protocol
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Record tip
        (map-set tips tip-id {
            tipper: caller,
            creator: creator,
            content-id: content-id,
            amount: creator-amount,
            message: message,
            timestamp: current-time
        })

        ;; Update creator profile
        (map-set creators creator (merge profile {
            total-tips-received: (+ (get total-tips-received profile) u1),
            total-amount-received: (+ (get total-amount-received profile) creator-amount),
            pending-balance: (+ (get pending-balance profile) creator-amount),
            supporter-count: (if (is-eq existing-support u0)
                (+ (get supporter-count profile) u1)
                (get supporter-count profile))
        }))

        ;; Update content stats if applicable
        (match content-id
            cid (match (map-get? content-items cid)
                content (map-set content-items cid (merge content {
                    tips-received: (+ (get tips-received content) u1),
                    total-amount: (+ (get total-amount content) creator-amount)
                }))
                true)
            true)

        ;; Track supporter
        (map-set creator-supporters { creator: creator, supporter: caller }
            (+ existing-support creator-amount))

        ;; Update counters
        (var-set tip-counter tip-id)
        (var-set total-tips-volume (+ (var-get total-tips-volume) amount))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))

        ;; Update tipper stats
        (update-tipper-stats caller amount fee)

        ;; EMIT EVENT: tip-sent
        (print {
            event: "tip-sent",
            tip-id: tip-id,
            tipper: caller,
            creator: creator,
            amount: creator-amount,
            fee: fee,
            content-id: content-id,
            has-message: (is-some message),
            timestamp: current-time
        })

        ;; EMIT EVENT: fee-collected
        (print {
            event: "fee-collected",
            tip-id: tip-id,
            fee-type: "tip",
            amount: fee,
            timestamp: current-time
        })

        (ok tip-id)))

;; Withdraw earnings
(define-public (withdraw-earnings (amount uint))
    (let
        (
            (caller tx-sender)
            (profile (unwrap! (map-get? creators caller) ERR_CREATOR_NOT_FOUND))
            (pending (get pending-balance profile))
            (current-time stacks-block-time)
        )
        ;; Validations
        (asserts! (<= amount pending) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Transfer to creator
        (try! (stx-transfer? amount (var-get contract-principal) caller))
        
        ;; Update balance
        (map-set creators caller (merge profile {
            pending-balance: (- pending amount)
        }))
        
        ;; EMIT EVENT: tip-withdrawn
        (print {
            event: "tip-withdrawn",
            creator: caller,
            amount: amount,
            remaining-balance: (- pending amount),
            timestamp: current-time
        })
        
        (ok amount)))

;; Update creator profile
(define-public (update-profile (bio (string-ascii 256)))
    (let
        (
            (caller tx-sender)
            (profile (unwrap! (map-get? creators caller) ERR_CREATOR_NOT_FOUND))
        )
        (map-set creators caller (merge profile { bio: bio }))
        
        ;; EMIT EVENT: profile-updated
        (print {
            event: "profile-updated",
            creator: caller,
            timestamp: stacks-block-time
        })
        
        (ok true)))

;; Create boost campaign (admin only)
(define-public (create-boost-campaign
    (name (string-ascii 64))
    (description (string-ascii 256))
    (multiplier uint)
    (duration uint))
    (let
        (
            (campaign-id (+ (var-get campaign-counter) u1))
            (current-time stacks-block-time)
            (end-time (+ current-time duration))
        )
        ;; Validations
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> multiplier u100) ERR_INVALID_MULTIPLIER)
        (asserts! (<= multiplier u500) ERR_INVALID_MULTIPLIER)
        (asserts! (> duration u3600) ERR_INVALID_AMOUNT)

        ;; Create campaign
        (map-set boost-campaigns campaign-id {
            name: name,
            description: description,
            multiplier: multiplier,
            start-time: current-time,
            end-time: end-time,
            active: true,
            total-boosted-tips: u0,
            total-participants: u0,
            created-by: tx-sender
        })

        (var-set campaign-counter campaign-id)

        ;; EMIT EVENT: campaign-created
        (print {
            event: "boost-campaign-created",
            campaign-id: campaign-id,
            name: name,
            multiplier: multiplier,
            start-time: current-time,
            end-time: end-time,
            timestamp: current-time
        })

        (ok campaign-id)))

;; Send boosted tip
(define-public (send-boosted-tip
    (creator principal)
    (amount uint)
    (campaign-id uint)
    (content-id (optional uint))
    (message (optional (string-ascii 256))))
    (let
        (
            (caller tx-sender)
            (profile (unwrap! (map-get? creators creator) ERR_CREATOR_NOT_FOUND))
            (campaign (unwrap! (map-get? boost-campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
            (tip-id (+ (var-get tip-counter) u1))
            (current-time stacks-block-time)
            (fee (calculate-fee amount))
            (creator-amount (- amount fee))
            (boost-amount (calculate-boosted-amount creator-amount campaign-id))
            (total-creator-amount (+ creator-amount boost-amount))
            (existing-support (default-to u0 (map-get? creator-supporters { creator: creator, supporter: caller })))
            (current-booster-stats (default-to
                { total-boosted-tips: u0, total-boost-amount: u0, campaigns-participated: u0, highest-single-boost: u0 }
                (map-get? booster-stats caller)))
        )
        ;; Validations
        (asserts! (>= amount MIN_TIP_AMOUNT) ERR_INVALID_AMOUNT)
        (asserts! (is-campaign-active campaign-id) ERR_CAMPAIGN_NOT_ACTIVE)
        (asserts! (> boost-amount u0) ERR_CAMPAIGN_NOT_ACTIVE)

        ;; Transfer tip (only base amount from tipper)
        (try! (stx-transfer? amount caller (var-get contract-principal)))

        ;; Transfer fee to protocol
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Record tip with boosted amount
        (map-set tips tip-id {
            tipper: caller,
            creator: creator,
            content-id: content-id,
            amount: total-creator-amount,
            message: message,
            timestamp: current-time
        })

        ;; Record boost details
        (map-set boosted-tips tip-id {
            campaign-id: campaign-id,
            original-amount: creator-amount,
            boosted-amount: boost-amount,
            multiplier: (get multiplier campaign)
        })

        ;; Update creator profile with boosted amount
        (map-set creators creator (merge profile {
            total-tips-received: (+ (get total-tips-received profile) u1),
            total-amount-received: (+ (get total-amount-received profile) total-creator-amount),
            pending-balance: (+ (get pending-balance profile) total-creator-amount),
            supporter-count: (if (is-eq existing-support u0)
                (+ (get supporter-count profile) u1)
                (get supporter-count profile))
        }))

        ;; Update content stats if applicable
        (match content-id
            cid (match (map-get? content-items cid)
                content (map-set content-items cid (merge content {
                    tips-received: (+ (get tips-received content) u1),
                    total-amount: (+ (get total-amount content) total-creator-amount)
                }))
                true)
            true)

        ;; Track supporter
        (map-set creator-supporters { creator: creator, supporter: caller }
            (+ existing-support total-creator-amount))

        ;; Update campaign stats
        (map-set boost-campaigns campaign-id (merge campaign {
            total-boosted-tips: (+ (get total-boosted-tips campaign) u1),
            total-participants: (+ (get total-participants campaign) u1)
        }))

        ;; Update booster stats
        (map-set booster-stats caller (merge current-booster-stats {
            total-boosted-tips: (+ (get total-boosted-tips current-booster-stats) u1),
            total-boost-amount: (+ (get total-boost-amount current-booster-stats) boost-amount),
            campaigns-participated: (+ (get campaigns-participated current-booster-stats) u1),
            highest-single-boost: (if (> boost-amount (get highest-single-boost current-booster-stats))
                                     boost-amount
                                     (get highest-single-boost current-booster-stats))
        }))

        ;; Update counters
        (var-set tip-counter tip-id)
        (var-set total-tips-volume (+ (var-get total-tips-volume) amount))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        (var-set total-boosted-tips (+ (var-get total-boosted-tips) u1))
        (var-set total-boost-multiplier-applied (+ (var-get total-boost-multiplier-applied) boost-amount))

        ;; Update tipper stats
        (update-tipper-stats caller amount fee)

        ;; EMIT EVENT: boosted-tip-sent
        (print {
            event: "boosted-tip-sent",
            tip-id: tip-id,
            campaign-id: campaign-id,
            tipper: caller,
            creator: creator,
            base-amount: creator-amount,
            boost-amount: boost-amount,
            total-amount: total-creator-amount,
            multiplier: (get multiplier campaign),
            fee: fee,
            content-id: content-id,
            has-message: (is-some message),
            timestamp: current-time
        })

        ;; EMIT EVENT: fee-collected
        (print {
            event: "fee-collected",
            tip-id: tip-id,
            fee-type: "boosted-tip",
            amount: fee,
            timestamp: current-time
        })

        (ok { tip-id: tip-id, boost-amount: boost-amount, total-amount: total-creator-amount })))

;; Toggle campaign status (admin only)
(define-public (toggle-campaign (campaign-id uint))
    (let
        (
            (campaign (unwrap! (map-get? boost-campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)

        (map-set boost-campaigns campaign-id (merge campaign {
            active: (not (get active campaign))
        }))

        ;; EMIT EVENT: campaign-toggled
        (print {
            event: "campaign-toggled",
            campaign-id: campaign-id,
            active: (not (get active campaign)),
            timestamp: stacks-block-time
        })

        (ok (not (get active campaign)))))

;; ========================================
;; Admin Functions
;; ========================================

;; Verify creator
(define-public (verify-creator (creator principal))
    (let
        (
            (profile (unwrap! (map-get? creators creator) ERR_CREATOR_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set creators creator (merge profile { verified: true }))
        
        ;; EMIT EVENT: creator-verified
        (print {
            event: "creator-verified",
            creator: creator,
            timestamp: stacks-block-time
        })

        (ok true)))

;; ========================================
;; Recurring Subscription Functions
;; ========================================

;; Create recurring subscription
(define-public (create-subscription (creator principal) (amount uint) (interval-seconds uint))
    (let ((existing-sub (map-get? subscriber-to-creator { subscriber: tx-sender, creator: creator }))
          (profile (unwrap! (map-get? creators creator) ERR_CREATOR_NOT_FOUND))
          (subscription-id (+ (var-get subscription-counter) u1))
          (current-time stacks-block-time)
          (next-payment (+ current-time interval-seconds)))
        ;; Validations
        (asserts! (>= amount MIN_TIP_AMOUNT) ERR_INVALID_AMOUNT)
        (asserts! (>= interval-seconds u86400) ERR_INVALID_AMOUNT) ;; Min 1 day
        (asserts! (is-none existing-sub) ERR_SUBSCRIPTION_ACTIVE)

        ;; Create subscription
        (map-set subscriptions subscription-id {
            subscriber: tx-sender,
            creator: creator,
            amount: amount,
            interval-seconds: interval-seconds,
            created-at: current-time,
            next-payment-due: next-payment,
            total-payments: u0,
            total-paid: u0,
            active: true,
            cancelled-at: none
        })

        ;; Link subscriber to creator
        (map-set subscriber-to-creator { subscriber: tx-sender, creator: creator } subscription-id)

        ;; Update counters
        (var-set subscription-counter subscription-id)
        (var-set total-active-subscriptions (+ (var-get total-active-subscriptions) u1))

        ;; Emit event
        (print {
            event: "subscription-created",
            subscription-id: subscription-id,
            subscriber: tx-sender,
            creator: creator,
            amount: amount,
            interval-seconds: interval-seconds,
            next-payment-due: next-payment,
            timestamp: current-time
        })

        (ok subscription-id)))

;; Process subscription payment
(define-public (process-subscription-payment (subscription-id uint))
    (let ((subscription (unwrap! (map-get? subscriptions subscription-id) ERR_SUBSCRIPTION_NOT_FOUND))
          (profile (unwrap! (map-get? creators (get creator subscription)) ERR_CREATOR_NOT_FOUND))
          (current-time stacks-block-time)
          (amount (get amount subscription))
          (fee (calculate-fee amount))
          (creator-amount (- amount fee))
          (tip-id (+ (var-get tip-counter) u1)))
        ;; Validations
        (asserts! (get active subscription) ERR_SUBSCRIPTION_CANCELLED)
        (asserts! (>= current-time (get next-payment-due subscription)) ERR_PAYMENT_NOT_DUE)

        ;; Transfer subscription payment
        (try! (stx-transfer? amount tx-sender (var-get contract-principal)))
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Record as tip
        (map-set tips tip-id {
            tipper: tx-sender,
            creator: (get creator subscription),
            content-id: none,
            amount: creator-amount,
            message: (some "Subscription payment"),
            timestamp: current-time
        })

        ;; Update creator profile
        (map-set creators (get creator subscription) (merge profile {
            total-tips-received: (+ (get total-tips-received profile) u1),
            total-amount-received: (+ (get total-amount-received profile) creator-amount),
            pending-balance: (+ (get pending-balance profile) creator-amount)
        }))

        ;; Update subscription
        (map-set subscriptions subscription-id (merge subscription {
            next-payment-due: (+ (get next-payment-due subscription) (get interval-seconds subscription)),
            total-payments: (+ (get total-payments subscription) u1),
            total-paid: (+ (get total-paid subscription) amount)
        }))

        ;; Update stats
        (var-set tip-counter tip-id)
        (var-set total-tips-volume (+ (var-get total-tips-volume) amount))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        (var-set total-subscription-revenue (+ (var-get total-subscription-revenue) creator-amount))

        ;; Update tipper stats
        (update-tipper-stats tx-sender amount fee)

        ;; Emit events
        (print {
            event: "subscription-payment-processed",
            subscription-id: subscription-id,
            tip-id: tip-id,
            subscriber: tx-sender,
            creator: (get creator subscription),
            amount: creator-amount,
            fee: fee,
            payment-number: (get total-payments subscription),
            next-payment-due: (+ (get next-payment-due subscription) (get interval-seconds subscription)),
            timestamp: current-time
        })

        (print {
            event: "fee-collected",
            tip-id: tip-id,
            fee-type: "subscription",
            amount: fee,
            timestamp: current-time
        })

        (ok { tip-id: tip-id, next-payment-due: (+ (get next-payment-due subscription) (get interval-seconds subscription)) })))

;; Cancel subscription
(define-public (cancel-subscription (subscription-id uint))
    (let ((subscription (unwrap! (map-get? subscriptions subscription-id) ERR_SUBSCRIPTION_NOT_FOUND)))
        ;; Validations
        (asserts! (is-eq tx-sender (get subscriber subscription)) ERR_NOT_AUTHORIZED)
        (asserts! (get active subscription) ERR_SUBSCRIPTION_CANCELLED)

        ;; Deactivate subscription
        (map-set subscriptions subscription-id (merge subscription {
            active: false,
            cancelled-at: (some stacks-block-time)
        }))

        ;; Remove mapping
        (map-delete subscriber-to-creator { subscriber: tx-sender, creator: (get creator subscription) })

        ;; Update counter
        (var-set total-active-subscriptions (- (var-get total-active-subscriptions) u1))

        ;; Emit event
        (print {
            event: "subscription-cancelled",
            subscription-id: subscription-id,
            subscriber: tx-sender,
            creator: (get creator subscription),
            total-payments-made: (get total-payments subscription),
            total-paid: (get total-paid subscription),
            timestamp: stacks-block-time
        })

        (ok true)))

;; Get subscription details
(define-read-only (get-subscription (subscription-id uint))
    (map-get? subscriptions subscription-id))

;; Check if payment is due
(define-read-only (is-payment-due (subscription-id uint))
    (match (map-get? subscriptions subscription-id)
        subscription {
            is-due: (and (get active subscription)
                        (>= stacks-block-time (get next-payment-due subscription))),
            next-payment-due: (get next-payment-due subscription),
            time-until-due: (if (> (get next-payment-due subscription) stacks-block-time)
                              (- (get next-payment-due subscription) stacks-block-time)
                              u0)
        }
        { is-due: false, next-payment-due: u0, time-until-due: u0 }))

;; Get subscription by subscriber and creator
(define-read-only (get-subscription-by-pair (subscriber principal) (creator principal))
    (match (map-get? subscriber-to-creator { subscriber: subscriber, creator: creator })
        sub-id (map-get? subscriptions sub-id)
        none))

;; Get subscription statistics
(define-read-only (get-subscription-stats)
    {
        total-subscriptions: (var-get subscription-counter),
        active-subscriptions: (var-get total-active-subscriptions),
        total-revenue: (var-get total-subscription-revenue)
    })

;; Leaderboard tracking for top tippers and creators
(define-map monthly-tip-totals { month: uint, tipper: principal } uint)
(define-map monthly-creator-earnings { month: uint, creator: principal } uint)
(define-data-var current-month uint u0)

(define-private (get-current-month) (/ stacks-block-time u2592000))

(define-public (record-tip-for-leaderboard (creator principal) (amount uint))
    (let ((month (get-current-month))
          (tipper-total (default-to u0 (map-get? monthly-tip-totals { month: month, tipper: tx-sender })))
          (creator-total (default-to u0 (map-get? monthly-creator-earnings { month: month, creator: creator }))))
        (map-set monthly-tip-totals { month: month, tipper: tx-sender } (+ tipper-total amount))
        (map-set monthly-creator-earnings { month: month, creator: creator } (+ creator-total amount))
        (print { event: "leaderboard-updated", month: month, tipper: tx-sender, creator: creator, amount: amount, timestamp: stacks-block-time })
        (ok true)))

(define-read-only (get-tipper-rank (month uint) (tipper principal))
    (default-to u0 (map-get? monthly-tip-totals { month: month, tipper: tipper })))

(define-read-only (get-creator-earnings (month uint) (creator principal))
    (default-to u0 (map-get? monthly-creator-earnings { month: month, creator: creator })))
