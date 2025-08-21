;; Billing Insurance Contract
;; Manages service billing, insurance claims, and payment processing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-CLAIM-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u403))
(define-constant ERR-INSUFFICIENT-AUTHORIZATION (err u404))

;; Data Variables
(define-data-var next-claim-id uint u1)
(define-data-var next-invoice-id uint u1)

;; Data Maps
(define-map insurance-claims
  { claim-id: uint }
  {
    patient-id: uint,
    provider: principal,
    service-date: uint,
    service-codes: (list 10 (string-ascii 20)),
    service-descriptions: (list 10 (string-ascii 200)),
    amounts: (list 10 uint),
    total-amount: uint,
    insurance-company: (string-ascii 100),
    policy-number: (string-ascii 50),
    authorization-number: (string-ascii 50),
    status: (string-ascii 20),
    submitted-date: uint,
    processed-date: uint,
    reimbursement-amount: uint
  }
)

(define-map service-invoices
  { invoice-id: uint }
  {
    patient-id: uint,
    provider: principal,
    service-date: uint,
    services: (list 10 (string-ascii 200)),
    amounts: (list 10 uint),
    total-amount: uint,
    payment-method: (string-ascii 30),
    payment-status: (string-ascii 20),
    due-date: uint,
    created-date: uint,
    paid-date: uint
  }
)

(define-map pre-authorizations
  { patient-id: uint, service-code: (string-ascii 20) }
  {
    authorization-number: (string-ascii 50),
    approved-sessions: uint,
    used-sessions: uint,
    expiry-date: uint,
    insurance-company: (string-ascii 100),
    authorized-by: principal,
    authorization-date: uint
  }
)

(define-map payment-records
  { claim-id: uint }
  {
    payment-amount: uint,
    payment-date: uint,
    payment-method: (string-ascii 30),
    transaction-id: (string-ascii 100),
    processed-by: principal
  }
)

(define-map authorized-billing-staff
  { staff: principal }
  { role: (string-ascii 30), active: bool }
)

;; Authorization Functions
(define-private (is-billing-authorized (user principal))
  (or
    (is-eq user CONTRACT-OWNER)
    (match (map-get? authorized-billing-staff { staff: user })
      staff-data (get active staff-data)
      false
    )
  )
)

;; Public Functions

;; Add authorized billing staff
(define-public (add-billing-staff (staff principal) (role (string-ascii 30)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-billing-staff
      { staff: staff }
      { role: role, active: true }
    ))
  )
)

;; Submit insurance claim
(define-public (submit-insurance-claim
  (patient-id uint)
  (provider principal)
  (service-date uint)
  (service-codes (list 10 (string-ascii 20)))
  (service-descriptions (list 10 (string-ascii 200)))
  (amounts (list 10 uint))
  (total-amount uint)
  (insurance-company (string-ascii 100))
  (policy-number (string-ascii 50))
  (authorization-number (string-ascii 50))
)
  (let
    (
      (claim-id (var-get next-claim-id))
    )
    (asserts! (is-billing-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> patient-id u0) ERR-INVALID-INPUT)
    (asserts! (> total-amount u0) ERR-INVALID-INPUT)
    (asserts! (<= service-date block-height) ERR-INVALID-INPUT)

    (map-set insurance-claims
      { claim-id: claim-id }
      {
        patient-id: patient-id,
        provider: provider,
        service-date: service-date,
        service-codes: service-codes,
        service-descriptions: service-descriptions,
        amounts: amounts,
        total-amount: total-amount,
        insurance-company: insurance-company,
        policy-number: policy-number,
        authorization-number: authorization-number,
        status: "submitted",
        submitted-date: block-height,
        processed-date: u0,
        reimbursement-amount: u0
      }
    )

    (var-set next-claim-id (+ claim-id u1))
    (ok claim-id)
  )
)

;; Process claim payment
(define-public (process-claim-payment
  (claim-id uint)
  (reimbursement-amount uint)
  (payment-method (string-ascii 30))
  (transaction-id (string-ascii 100))
)
  (let
    (
      (claim-data (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR-CLAIM-NOT-FOUND))
    )
    (asserts! (is-billing-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status claim-data) "submitted") ERR-CLAIM-ALREADY-PROCESSED)

    ;; Update claim status
    (map-set insurance-claims
      { claim-id: claim-id }
      (merge claim-data {
        status: "processed",
        processed-date: block-height,
        reimbursement-amount: reimbursement-amount
      })
    )

    ;; Record payment
    (map-set payment-records
      { claim-id: claim-id }
      {
        payment-amount: reimbursement-amount,
        payment-date: block-height,
        payment-method: payment-method,
        transaction-id: transaction-id,
        processed-by: tx-sender
      }
    )

    (ok true)
  )
)

;; Create service invoice
(define-public (create-invoice
  (patient-id uint)
  (provider principal)
  (service-date uint)
  (services (list 10 (string-ascii 200)))
  (amounts (list 10 uint))
  (total-amount uint)
  (payment-method (string-ascii 30))
  (due-date uint)
)
  (let
    (
      (invoice-id (var-get next-invoice-id))
    )
    (asserts! (is-billing-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> patient-id u0) ERR-INVALID-INPUT)
    (asserts! (> total-amount u0) ERR-INVALID-INPUT)
    (asserts! (> due-date block-height) ERR-INVALID-INPUT)

    (map-set service-invoices
      { invoice-id: invoice-id }
      {
        patient-id: patient-id,
        provider: provider,
        service-date: service-date,
        services: services,
        amounts: amounts,
        total-amount: total-amount,
        payment-method: payment-method,
        payment-status: "pending",
        due-date: due-date,
        created-date: block-height,
        paid-date: u0
      }
    )

    (var-set next-invoice-id (+ invoice-id u1))
    (ok invoice-id)
  )
)

;; Add pre-authorization
(define-public (add-pre-authorization
  (patient-id uint)
  (service-code (string-ascii 20))
  (authorization-number (string-ascii 50))
  (approved-sessions uint)
  (expiry-date uint)
  (insurance-company (string-ascii 100))
)
  (begin
    (asserts! (is-billing-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> patient-id u0) ERR-INVALID-INPUT)
    (asserts! (> approved-sessions u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date block-height) ERR-INVALID-INPUT)

    (ok (map-set pre-authorizations
      { patient-id: patient-id, service-code: service-code }
      {
        authorization-number: authorization-number,
        approved-sessions: approved-sessions,
        used-sessions: u0,
        expiry-date: expiry-date,
        insurance-company: insurance-company,
        authorized-by: tx-sender,
        authorization-date: block-height
      }
    ))
  )
)

;; Use pre-authorization session
(define-public (use-authorization-session (patient-id uint) (service-code (string-ascii 20)))
  (let
    (
      (auth-data (unwrap! (map-get? pre-authorizations { patient-id: patient-id, service-code: service-code }) ERR-INSUFFICIENT-AUTHORIZATION))
    )
    (asserts! (is-billing-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (< (get used-sessions auth-data) (get approved-sessions auth-data)) ERR-INSUFFICIENT-AUTHORIZATION)
    (asserts! (> (get expiry-date auth-data) block-height) ERR-INSUFFICIENT-AUTHORIZATION)

    (ok (map-set pre-authorizations
      { patient-id: patient-id, service-code: service-code }
      (merge auth-data { used-sessions: (+ (get used-sessions auth-data) u1) })
    ))
  )
)

;; Read-only Functions

;; Get insurance claim
(define-read-only (get-insurance-claim (claim-id uint))
  (map-get? insurance-claims { claim-id: claim-id })
)

;; Get service invoice
(define-read-only (get-service-invoice (invoice-id uint))
  (map-get? service-invoices { invoice-id: invoice-id })
)

;; Get pre-authorization
(define-read-only (get-pre-authorization (patient-id uint) (service-code (string-ascii 20)))
  (map-get? pre-authorizations { patient-id: patient-id, service-code: service-code })
)

;; Get payment record
(define-read-only (get-payment-record (claim-id uint))
  (map-get? payment-records { claim-id: claim-id })
)

;; Check authorization availability
(define-read-only (check-authorization-availability (patient-id uint) (service-code (string-ascii 20)))
  (match (map-get? pre-authorizations { patient-id: patient-id, service-code: service-code })
    auth-data (and
      (< (get used-sessions auth-data) (get approved-sessions auth-data))
      (> (get expiry-date auth-data) block-height)
    )
    false
  )
)
