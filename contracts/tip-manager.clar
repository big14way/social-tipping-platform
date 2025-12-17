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
        current-time: stacks-block-time
    })

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
