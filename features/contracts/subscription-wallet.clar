;; Subscription Wallet Contract
;; Enables recurring payments to farmers with escrow protection

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_CONFIRMED (err u103))
(define-constant ERR_DELIVERY_WINDOW_EXPIRED (err u104))

;; Data structures
(define-map subscriptions
  { subscriber: principal, farmer: principal }
  {
    amount: uint,
    interval: uint,  ;; blocks between payments
    next-payment: uint,  ;; block height
    balance: uint,
    active: bool,
    delivery-window: uint  ;; blocks to confirm delivery
  }
)

(define-map pending-deliveries
  { order-id: uint }
  {
    subscriber: principal,
    farmer: principal,
    amount: uint,
    created-at: uint,
    deadline: uint,
    confirmed: bool
  }
)

(define-data-var order-counter uint u0)

;; Create subscription
(define-public (create-subscription 
  (farmer principal) 
  (amount uint) 
  (interval uint) 
  (delivery-window uint))
  (let 
    ((subscription-key { subscriber: tx-sender, farmer: farmer }))
    (asserts! (> amount u0) ERR_INSUFFICIENT_FUNDS)
    (map-set subscriptions subscription-key {
      amount: amount,
      interval: interval,
      next-payment: (+ stacks-block-height interval),
      balance: u0,
      active: true,
      delivery-window: delivery-window
    })
    (ok true)
  )
)

;; Deposit funds to subscription
(define-public (deposit-funds (farmer principal) (amount uint))
  (let 
    ((subscription-key { subscriber: tx-sender, farmer: farmer })
     (subscription-data (unwrap! (map-get? subscriptions subscription-key) ERR_SUBSCRIPTION_NOT_FOUND)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set subscriptions subscription-key 
      (merge subscription-data { balance: (+ (get balance subscription-data) amount) }))
    (ok amount)
  )
)

;; Process scheduled payment
(define-public (process-payment (subscriber principal) (farmer principal))
  (let 
    ((subscription-key { subscriber: subscriber, farmer: farmer })
     (subscription-data (unwrap! (map-get? subscriptions subscription-key) ERR_SUBSCRIPTION_NOT_FOUND))
     (order-id (+ (var-get order-counter) u1)))
    
    (asserts! (>= stacks-block-height (get next-payment subscription-data)) (err u105))
    (asserts! (get active subscription-data) (err u106))
    (asserts! (>= (get balance subscription-data) (get amount subscription-data)) ERR_INSUFFICIENT_FUNDS)
    
    ;; Create pending delivery
    (map-set pending-deliveries { order-id: order-id } {
      subscriber: subscriber,
      farmer: farmer,
      amount: (get amount subscription-data),
      created-at: stacks-block-height,
      deadline: (+ stacks-block-height (get delivery-window subscription-data)),
      confirmed: false
    })
    
    ;; Update subscription
    (map-set subscriptions subscription-key 
      (merge subscription-data { 
        balance: (- (get balance subscription-data) (get amount subscription-data)),
        next-payment: (+ stacks-block-height (get interval subscription-data))
      }))
    
    (var-set order-counter order-id)
    (ok order-id)
  )
)

;; Confirm delivery and release payment
(define-public (confirm-delivery (order-id uint))
  (let 
    ((delivery-data (unwrap! (map-get? pending-deliveries { order-id: order-id }) ERR_SUBSCRIPTION_NOT_FOUND)))
    
    (asserts! (is-eq tx-sender (get subscriber delivery-data)) ERR_UNAUTHORIZED)
    (asserts! (not (get confirmed delivery-data)) ERR_ALREADY_CONFIRMED)
    (asserts! (<= stacks-block-height (get deadline delivery-data)) ERR_DELIVERY_WINDOW_EXPIRED)
    
    ;; Release payment to farmer
    (try! (as-contract (stx-transfer? (get amount delivery-data) tx-sender (get farmer delivery-data))))
    
    ;; Mark as confirmed
    (map-set pending-deliveries { order-id: order-id }
      (merge delivery-data { confirmed: true }))
    
    (ok true)
  )
)

;; Cancel subscription
(define-public (cancel-subscription (farmer principal))
  (let 
    ((subscription-key { subscriber: tx-sender, farmer: farmer })
     (subscription-data (unwrap! (map-get? subscriptions subscription-key) ERR_SUBSCRIPTION_NOT_FOUND)))
    
    (map-set subscriptions subscription-key 
      (merge subscription-data { active: false }))
    
    ;; Refund remaining balance if any
    (if (> (get balance subscription-data) u0)
        (try! (as-contract (stx-transfer? (get balance subscription-data) tx-sender tx-sender)))
        true)
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-subscription (subscriber principal) (farmer principal))
  (map-get? subscriptions { subscriber: subscriber, farmer: farmer })
)

(define-read-only (get-delivery (order-id uint))
  (map-get? pending-deliveries { order-id: order-id })
)