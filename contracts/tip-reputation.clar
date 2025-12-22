;; tip-reputation.clar
;; Creator and tipper reputation system with quality scoring
;; Uses Clarity 4 epoch 3.3 with Chainhook integration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u12001))
(define-constant ERR_INVALID_SCORE (err u12002))
(define-constant ERR_REPUTATION_NOT_FOUND (err u12003))
(define-constant ERR_ALREADY_REVIEWED (err u12004))

(define-data-var review-counter uint u0)
(define-data-var total-reputation-points uint u0)

;; User reputation scores
(define-map user-reputation
    principal
    {
        creator-score: uint,
        tipper-score: uint,
        total-tips-given: uint,
        total-tips-received: uint,
        quality-rating: uint,
        consistency-score: uint,
        verified: bool,
        created-at: uint,
        last-updated: uint
    }
)

;; Quality reviews
(define-map quality-reviews
    { reviewer: principal, reviewed: principal, review-id: uint }
    {
        quality-score: uint,
        authenticity-score: uint,
        engagement-score: uint,
        comment: (string-utf8 256),
        reviewed-at: uint,
        helpful-votes: uint
    }
)

;; Reputation badges
(define-map reputation-badges
    { user: principal, badge-type: (string-ascii 32) }
    {
        earned-at: uint,
        tier: uint,
        active: bool
    }
)

;; Reputation milestones
(define-map reputation-milestones
    uint
    {
        milestone-name: (string-ascii 64),
        required-score: uint,
        reward-points: uint,
        badge-type: (string-ascii 32)
    }
)

(define-data-var milestone-counter uint u0)

(define-public (initialize-reputation (user principal))
    (let
        (
            (existing (map-get? user-reputation user))
        )
        (asserts! (is-none existing) (ok false))
        (map-set user-reputation user {
            creator-score: u0,
            tipper-score: u0,
            total-tips-given: u0,
            total-tips-received: u0,
            quality-rating: u0,
            consistency-score: u0,
            verified: false,
            created-at: stacks-block-time,
            last-updated: stacks-block-time
        })
        (print {
            event: "reputation-initialized",
            user: user,
            timestamp: stacks-block-time
        })
        (ok true)
    )
)

(define-public (update-tipper-reputation (tipper principal) (points uint))
    (let
        (
            (rep (unwrap! (map-get? user-reputation tipper) ERR_REPUTATION_NOT_FOUND))
            (new-tipper-score (+ (get tipper-score rep) points))
        )
        (map-set user-reputation tipper
            (merge rep {
                tipper-score: new-tipper-score,
                total-tips-given: (+ (get total-tips-given rep) u1),
                last-updated: stacks-block-time
            }))
        (var-set total-reputation-points (+ (var-get total-reputation-points) points))
        (print {
            event: "tipper-reputation-updated",
            tipper: tipper,
            points-added: points,
            new-score: new-tipper-score,
            timestamp: stacks-block-time
        })
        (ok new-tipper-score)
    )
)

(define-public (update-creator-reputation (creator principal) (points uint))
    (let
        (
            (rep (unwrap! (map-get? user-reputation creator) ERR_REPUTATION_NOT_FOUND))
            (new-creator-score (+ (get creator-score rep) points))
        )
        (map-set user-reputation creator
            (merge rep {
                creator-score: new-creator-score,
                total-tips-received: (+ (get total-tips-received rep) u1),
                last-updated: stacks-block-time
            }))
        (print {
            event: "creator-reputation-updated",
            creator: creator,
            points-added: points,
            new-score: new-creator-score,
            timestamp: stacks-block-time
        })
        (ok new-creator-score)
    )
)

(define-public (submit-quality-review
    (reviewed principal)
    (quality-score uint)
    (authenticity-score uint)
    (engagement-score uint)
    (comment (string-utf8 256)))
    (let
        (
            (reviewer tx-sender)
            (review-id (+ (var-get review-counter) u1))
        )
        (asserts! (<= quality-score u100) ERR_INVALID_SCORE)
        (asserts! (<= authenticity-score u100) ERR_INVALID_SCORE)
        (asserts! (<= engagement-score u100) ERR_INVALID_SCORE)
        (asserts! (is-none (map-get? quality-reviews { reviewer: reviewer, reviewed: reviewed, review-id: review-id })) ERR_ALREADY_REVIEWED)
        
        (map-set quality-reviews
            { reviewer: reviewer, reviewed: reviewed, review-id: review-id }
            {
                quality-score: quality-score,
                authenticity-score: authenticity-score,
                engagement-score: engagement-score,
                comment: comment,
                reviewed-at: stacks-block-time,
                helpful-votes: u0
            })
        (var-set review-counter review-id)
        (print {
            event: "quality-review-submitted",
            reviewer: reviewer,
            reviewed: reviewed,
            review-id: review-id,
            quality-score: quality-score,
            timestamp: stacks-block-time
        })
        (ok review-id)
    )
)

(define-public (award-badge (user principal) (badge-type (string-ascii 32)) (tier uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set reputation-badges
            { user: user, badge-type: badge-type }
            {
                earned-at: stacks-block-time,
                tier: tier,
                active: true
            })
        (print {
            event: "badge-awarded",
            user: user,
            badge-type: badge-type,
            tier: tier,
            timestamp: stacks-block-time
        })
        (ok true)
    )
)

(define-read-only (get-user-reputation (user principal))
    (map-get? user-reputation user)
)

(define-read-only (get-quality-review (reviewer principal) (reviewed principal) (review-id uint))
    (map-get? quality-reviews { reviewer: reviewer, reviewed: reviewed, review-id: review-id })
)

(define-read-only (get-badge (user principal) (badge-type (string-ascii 32)))
    (map-get? reputation-badges { user: user, badge-type: badge-type })
)

(define-read-only (calculate-overall-score (user principal))
    (match (get-user-reputation user)
        rep (ok {
            overall-score: (+ (get creator-score rep) (get tipper-score rep)),
            creator-score: (get creator-score rep),
            tipper-score: (get tipper-score rep),
            quality-rating: (get quality-rating rep)
        })
        (err ERR_REPUTATION_NOT_FOUND))
)
