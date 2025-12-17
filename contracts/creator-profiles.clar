;; creator-profiles.clar
;; Extended creator profiles with badges, milestones, and achievements

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u22101))
(define-constant ERR_BADGE_NOT_FOUND (err u22102))

;; Badge types
(define-constant BADGE_VERIFIED u0)
(define-constant BADGE_TOP_CREATOR u1)
(define-constant BADGE_RISING_STAR u2)
(define-constant BADGE_COMMUNITY_FAVORITE u3)

;; Milestone thresholds
(define-constant MILESTONE_10_TIPS u10)
(define-constant MILESTONE_100_TIPS u100)
(define-constant MILESTONE_1000_TIPS u1000)

;; ========================================
;; Data Maps
;; ========================================

(define-map creator-badges
    { creator: principal, badge-type: uint }
    {
        awarded-at: uint,
        awarded-by: principal
    }
)

(define-map creator-milestones
    principal
    {
        tips-10: bool,
        tips-100: bool,
        tips-1000: bool,
        first-supporter: bool,
        first-content: bool
    }
)

(define-map badge-metadata
    uint
    {
        name: (string-ascii 32),
        description: (string-ascii 128)
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (has-badge (creator principal) (badge-type uint))
    (is-some (map-get? creator-badges { creator: creator, badge-type: badge-type })))

(define-read-only (get-milestones (creator principal))
    (default-to 
        { tips-10: false, tips-100: false, tips-1000: false, first-supporter: false, first-content: false }
        (map-get? creator-milestones creator)))

(define-read-only (get-badge-info (badge-type uint))
    (map-get? badge-metadata badge-type))

;; ========================================
;; Public Functions
;; ========================================

;; Award badge (admin only)
(define-public (award-badge (creator principal) (badge-type uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set creator-badges { creator: creator, badge-type: badge-type } {
            awarded-at: stacks-block-time,
            awarded-by: tx-sender
        })
        
        ;; EMIT EVENT: badge-awarded
        (print {
            event: "badge-awarded",
            creator: creator,
            badge-type: badge-type,
            timestamp: stacks-block-time
        })
        
        (ok true)))

;; Check and award milestones
(define-public (check-milestone (creator principal) (tips-count uint))
    (let
        (
            (current-milestones (get-milestones creator))
        )
        ;; Check 10 tips
        (if (and (>= tips-count MILESTONE_10_TIPS) (not (get tips-10 current-milestones)))
            (begin
                (map-set creator-milestones creator (merge current-milestones { tips-10: true }))
                (print {
                    event: "milestone-reached",
                    creator: creator,
                    milestone: "10-tips",
                    timestamp: stacks-block-time
                })
                true)
            true)

        ;; Check 100 tips
        (if (and (>= tips-count MILESTONE_100_TIPS) (not (get tips-100 current-milestones)))
            (begin
                (map-set creator-milestones creator (merge (get-milestones creator) { tips-100: true }))
                (print {
                    event: "milestone-reached",
                    creator: creator,
                    milestone: "100-tips",
                    timestamp: stacks-block-time
                })
                true)
            true)

        ;; Check 1000 tips
        (if (and (>= tips-count MILESTONE_1000_TIPS) (not (get tips-1000 current-milestones)))
            (begin
                (map-set creator-milestones creator (merge (get-milestones creator) { tips-1000: true }))
                (print {
                    event: "milestone-reached",
                    creator: creator,
                    milestone: "1000-tips",
                    timestamp: stacks-block-time
                })
                true)
            true)
        
        (ok true)))

;; Initialize badge metadata
(define-public (initialize-badges)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set badge-metadata BADGE_VERIFIED {
            name: "Verified Creator",
            description: "Identity verified by platform"
        })
        (map-set badge-metadata BADGE_TOP_CREATOR {
            name: "Top Creator",
            description: "Top 10 by earnings"
        })
        (map-set badge-metadata BADGE_RISING_STAR {
            name: "Rising Star",
            description: "Fastest growing creator this month"
        })
        (map-set badge-metadata BADGE_COMMUNITY_FAVORITE {
            name: "Community Favorite",
            description: "Most supporters this month"
        })
        
        (ok true)))
