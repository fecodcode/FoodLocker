;; Delivery Confirmation NFT - Immutable delivery receipt system
;; Version: 1.0.0

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-NFT-NOT-FOUND (err u301))
(define-constant ERR-ALREADY-CONFIRMED (err u302))
(define-constant ERR-INVALID-AGENT (err u303))

(define-constant CONTRACT-OWNER tx-sender)

;; NFT Definition
(define-non-fungible-token delivery-nft uint)

;; Data Variables
(define-data-var nft-counter uint u0)

;; Maps
(define-map delivery-records
  { token-id: uint }
  {
    order-id: uint,
    buyer: principal,
    seller: principal,
    agent: principal,
    timestamp: uint,
    quality-flag: uint,
    photo-hash: (string-ascii 64)
  }
)

(define-map authorized-agents
  { agent: principal }
  { active: bool }
)

(define-map order-confirmations
  { order-id: uint }
  { confirmed: bool, token-id: uint }
)

;; Read-only functions
(define-read-only (get-last-token-id)
  (ok (var-get nft-counter))
)

(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat "ipfs://" (get photo-hash (unwrap! (map-get? delivery-records { token-id: token-id }) ERR-NFT-NOT-FOUND)))))
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? delivery-nft token-id))
)

(define-read-only (get-delivery-record (token-id uint))
  (ok (map-get? delivery-records { token-id: token-id }))
)

(define-read-only (is-agent (agent principal))
  (default-to false
    (get active (map-get? authorized-agents { agent: agent }))
  )
)

(define-read-only (is-order-confirmed (order-id uint))
  (default-to false
    (get confirmed (map-get? order-confirmations { order-id: order-id }))
  )
)

;; Admin functions
(define-public (add-agent (agent principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-agents
      { agent: agent }
      { active: true }
    )
    (ok true)
  )
)

(define-public (remove-agent (agent principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-agents
      { agent: agent }
      { active: false }
    )
    (ok true)
  )
)

;; Mint delivery NFT
(define-public (confirm-delivery 
    (order-id uint)
    (buyer principal)
    (seller principal)
    (quality-flag uint)
    (photo-hash (string-ascii 64)))
  (let ((token-id (+ (var-get nft-counter) u1)))
    (asserts! (or (is-agent tx-sender) (is-eq tx-sender buyer)) ERR-INVALID-AGENT)
    (asserts! (not (is-order-confirmed order-id)) ERR-ALREADY-CONFIRMED)
    
    (try! (nft-mint? delivery-nft token-id buyer))
    
    (map-set delivery-records
      { token-id: token-id }
      {
        order-id: order-id,
        buyer: buyer,
        seller: seller,
        agent: tx-sender,
        timestamp: stacks-block-height,
        quality-flag: quality-flag,
        photo-hash: photo-hash
      }
    )
    
    (map-set order-confirmations
      { order-id: order-id }
      { confirmed: true, token-id: token-id }
    )
    
    (var-set nft-counter token-id)
    (ok token-id)
  )
)

;; Transfer NFT (optional - can be disabled for non-transferable)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq sender (unwrap! (nft-get-owner? delivery-nft token-id) ERR-NFT-NOT-FOUND)) ERR-NOT-AUTHORIZED)
    (nft-transfer? delivery-nft token-id sender recipient)
  )
)

;; Get delivery details by order
(define-read-only (get-confirmation-by-order (order-id uint))
  (match (map-get? order-confirmations { order-id: order-id })
    confirmation
    (ok {
      confirmed: (get confirmed confirmation),
      token-id: (get token-id confirmation),
      record: (map-get? delivery-records { token-id: (get token-id confirmation) })
    })
    (ok { confirmed: false, token-id: u0, record: none })
  )
)