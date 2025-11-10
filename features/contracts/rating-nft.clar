;; Farmer Identity & Rating NFTs (SBT-style)
;; Issues verified farmer identity and progressive reputation badges

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-FARMER-NOT-FOUND (err u401))
(define-constant ERR-ISSUER-NOT-FOUND (err u402))
(define-constant ERR-ALREADY-HAS-SBT (err u403))
(define-constant ERR-INVALID-TIER (err u404))
(define-constant ERR-INSUFFICIENT-DELIVERIES (err u405))

;; Rating tiers
(define-constant TIER-NONE u0)
(define-constant TIER-BRONZE u1)
(define-constant TIER-SILVER u2)
(define-constant TIER-GOLD u3)

;; SBT Definition
(define-non-fungible-token farmer-sbt uint)

;; Data Variables
(define-data-var nft-counter uint u0)

;; Maps
(define-map farmer-records
  { farmer: principal }
  {
    identity-sbt: uint,
    current-tier: uint,
    completed-deliveries: uint,
    disputes: uint,
    timeliness-score: uint,
    issued-at: uint,
    last-updated: uint
  }
)

(define-map tier-sbt-tokens
  { farmer: principal, tier: uint }
  { token-id: uint }
)

(define-map authorized-issuers
  { issuer: principal }
  { active: bool }
)

;; Read-only functions
(define-read-only (get-farmer-record (farmer principal))
  (map-get? farmer-records { farmer: farmer })
)

(define-read-only (get-tier-sbt (farmer principal) (tier uint))
  (map-get? tier-sbt-tokens { farmer: farmer, tier: tier })
)

(define-read-only (is-authorized-issuer (issuer principal))
  (default-to false
    (get active (map-get? authorized-issuers { issuer: issuer }))
  )
)

(define-read-only (get-current-tier (farmer principal))
  (match (map-get? farmer-records { farmer: farmer })
    record (ok (get current-tier record))
    (ok u0)
  )
)

;; Admin functions
(define-public (add-issuer (issuer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-issuers
      { issuer: issuer }
      { active: true }
    )
    (ok true)
  )
)

(define-public (remove-issuer (issuer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-issuers
      { issuer: issuer }
      { active: false }
    )
    (ok true)
  )
)

;; Mint identity SBT for farmer
(define-public (issue-farmer-identity (farmer principal))
  (let ((identity-token-id (+ (var-get nft-counter) u1)))
    (asserts! (is-authorized-issuer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? farmer-records { farmer: farmer })) ERR-ALREADY-HAS-SBT)
    
    (try! (nft-mint? farmer-sbt identity-token-id farmer))
    
    (map-set farmer-records
      { farmer: farmer }
      {
        identity-sbt: identity-token-id,
        current-tier: TIER-NONE,
        completed-deliveries: u0,
        disputes: u0,
        timeliness-score: u100,
        issued-at: stacks-block-height,
        last-updated: stacks-block-height
      }
    )
    
    (var-set nft-counter identity-token-id)
    (ok identity-token-id)
  )
)

;; Update farmer stats and calculate tier
(define-public (update-farmer-stats 
  (farmer principal)
  (completed-deliveries uint)
  (disputes uint)
  (timeliness-score uint))
  (let 
    ((farmer-data (unwrap! (map-get? farmer-records { farmer: farmer }) ERR-FARMER-NOT-FOUND))
     (new-tier (calculate-tier completed-deliveries disputes timeliness-score)))
    
    (asserts! (is-authorized-issuer tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Update farmer record
    (map-set farmer-records
      { farmer: farmer }
      {
        identity-sbt: (get identity-sbt farmer-data),
        current-tier: new-tier,
        completed-deliveries: completed-deliveries,
        disputes: disputes,
        timeliness-score: timeliness-score,
        issued-at: (get issued-at farmer-data),
        last-updated: stacks-block-height
      }
    )
    
    ;; Mint tier SBT if tier changed
    (if (> new-tier TIER-NONE)
      (let ((tier-token-id (+ (var-get nft-counter) u1)))
        (try! (nft-mint? farmer-sbt tier-token-id farmer))
        (map-set tier-sbt-tokens
          { farmer: farmer, tier: new-tier }
          { token-id: tier-token-id }
        )
        (var-set nft-counter tier-token-id)
      )
      true
    )
    
    (ok new-tier)
  )
)

;; Calculate tier based on performance
(define-read-only (calculate-tier 
  (completed-deliveries uint)
  (disputes uint)
  (timeliness-score uint))
  (if (< disputes u1)
    (if (>= completed-deliveries u50)
      (if (>= timeliness-score u95)
        TIER-GOLD
        TIER-SILVER
      )
      (if (>= completed-deliveries u10)
        TIER-BRONZE
        TIER-NONE
      )
    )
    TIER-NONE
  )
)

;; Get SBT owner
(define-read-only (get-sbt-owner (token-id uint))
  (ok (nft-get-owner? farmer-sbt token-id))
)
