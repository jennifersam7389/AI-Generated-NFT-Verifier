(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_METADATA (err u103))
(define-constant ERR_VERIFICATION_FAILED (err u104))
(define-constant ERR_INVALID_AI_MODEL (err u105))

(define-data-var next-verification-id uint u1)
(define-data-var verification-fee uint u1000000)
(define-data-var next-batch-id uint u1)
(define-data-var batch-discount-rate uint u10)

(define-map verified-nfts
    { contract-address: principal, token-id: uint }
    {
        verification-id: uint,
        ai-model: (string-ascii 50),
        confidence-score: uint,
        verifier: principal,
        timestamp: uint,
        metadata-hash: (buff 32),
        is-verified: bool
    }
)

(define-map ai-models
    (string-ascii 50)
    {
        model-name: (string-ascii 100),
        version: (string-ascii 20),
        accuracy-threshold: uint,
        is-active: bool,
        registered-by: principal
    }
)

(define-map verifier-credentials
    principal
    {
        reputation-score: uint,
        total-verifications: uint,
        successful-verifications: uint,
        is-certified: bool,
        certification-date: uint
    }
)

(define-map verification-requests
    uint
    {
        contract-address: principal,
        token-id: uint,
        requester: principal,
        ai-model-requested: (string-ascii 50),
        status: (string-ascii 20),
        created-at: uint,
        fee-paid: uint
    }
)

(define-map batch-verification-requests
    uint
    {
        requester: principal,
        ai-model-requested: (string-ascii 50),
        nft-count: uint,
        status: (string-ascii 20),
        created-at: uint,
        total-fee-paid: uint,
        completed-count: uint
    }
)

(define-map batch-nft-items
    { batch-id: uint, item-index: uint }
    {
        contract-address: principal,
        token-id: uint,
        verification-id: uint,
        is-completed: bool
    }
)

(define-public (register-ai-model (model-id (string-ascii 50)) (model-name (string-ascii 100)) (version (string-ascii 20)) (accuracy-threshold uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-none (map-get? ai-models model-id)) ERR_ALREADY_EXISTS)
        (asserts! (and (>= accuracy-threshold u70) (<= accuracy-threshold u100)) ERR_INVALID_AI_MODEL)
        (ok (map-set ai-models model-id {
            model-name: model-name,
            version: version,
            accuracy-threshold: accuracy-threshold,
            is-active: true,
            registered-by: tx-sender
        }))
    )
)

(define-public (certify-verifier (verifier principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (map-set verifier-credentials verifier {
            reputation-score: u100,
            total-verifications: u0,
            successful-verifications: u0,
            is-certified: true,
            certification-date: stacks-block-height
        }))
    )
)

(define-public (request-verification (contract-address principal) (token-id uint) (ai-model (string-ascii 50)))
    (let (
        (verification-id (var-get next-verification-id))
        (fee (var-get verification-fee))
    )
        (asserts! (is-some (map-get? ai-models ai-model)) ERR_INVALID_AI_MODEL)
        (asserts! (is-none (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })) ERR_ALREADY_EXISTS)
        (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
        (map-set verification-requests verification-id {
            contract-address: contract-address,
            token-id: token-id,
            requester: tx-sender,
            ai-model-requested: ai-model,
            status: "pending",
            created-at: stacks-block-height,
            fee-paid: fee
        })
        (var-set next-verification-id (+ verification-id u1))
        (ok verification-id)
    )
)

(define-public (submit-verification 
    (verification-id uint)
    (contract-address principal) 
    (token-id uint) 
    (ai-model (string-ascii 50)) 
    (confidence-score uint) 
    (metadata-hash (buff 32))
)
    (let (
        (verifier-data (default-to 
            { reputation-score: u0, total-verifications: u0, successful-verifications: u0, is-certified: false, certification-date: u0 }
            (map-get? verifier-credentials tx-sender)
        ))
        (model-data (unwrap! (map-get? ai-models ai-model) ERR_INVALID_AI_MODEL))
        (request-data (unwrap! (map-get? verification-requests verification-id) ERR_NOT_FOUND))
        (is-verified (>= confidence-score (get accuracy-threshold model-data)))
    )
        (asserts! (get is-certified verifier-data) ERR_UNAUTHORIZED)
        (asserts! (get is-active model-data) ERR_INVALID_AI_MODEL)
        (asserts! (is-eq (get status request-data) "pending") ERR_VERIFICATION_FAILED)
        (asserts! (and (is-eq (get contract-address request-data) contract-address) 
                      (is-eq (get token-id request-data) token-id)) ERR_VERIFICATION_FAILED)
        (asserts! (and (>= confidence-score u0) (<= confidence-score u100)) ERR_INVALID_METADATA)
        
        (map-set verified-nfts 
            { contract-address: contract-address, token-id: token-id }
            {
                verification-id: verification-id,
                ai-model: ai-model,
                confidence-score: confidence-score,
                verifier: tx-sender,
                timestamp: stacks-block-height,
                metadata-hash: metadata-hash,
                is-verified: is-verified
            }
        )
        
        (map-set verification-requests verification-id 
            (merge request-data { status: "completed" })
        )
        
        (map-set verifier-credentials tx-sender {
            reputation-score: (get reputation-score verifier-data),
            total-verifications: (+ (get total-verifications verifier-data) u1),
            successful-verifications: (+ (get successful-verifications verifier-data) (if is-verified u1 u0)),
            is-certified: true,
            certification-date: (get certification-date verifier-data)
        })
        
        (ok is-verified)
    )
)

(define-public (request-batch-verification (nft-list (list 50 { contract-address: principal, token-id: uint })) (ai-model (string-ascii 50)))
    (let (
        (batch-id (var-get next-batch-id))
        (nft-count (len nft-list))
        (base-fee (var-get verification-fee))
        (discount-rate (var-get batch-discount-rate))
        (discount-amount (/ (* base-fee nft-count discount-rate) u100))
        (total-fee (- (* base-fee nft-count) discount-amount))
        (block-height-current stacks-block-height)
    )
        (asserts! (is-some (map-get? ai-models ai-model)) ERR_INVALID_AI_MODEL)
        (asserts! (> nft-count u1) ERR_INVALID_METADATA)
        (asserts! (<= nft-count u50) ERR_INVALID_METADATA)
        (try! (stx-transfer? total-fee tx-sender (as-contract tx-sender)))
        (map-set batch-verification-requests batch-id {
            requester: tx-sender,
            ai-model-requested: ai-model,
            nft-count: nft-count,
            status: "pending",
            created-at: block-height-current,
            total-fee-paid: total-fee,
            completed-count: u0
        })
        (var-set next-batch-id (+ batch-id u1))
        (fold store-single-nft-item nft-list u0)
        (ok batch-id)
    )
)



(define-private (store-single-nft-item (nft-item { contract-address: principal, token-id: uint }) (current-index uint))
    (let (
        (batch-id (- (var-get next-batch-id) u1))
        (verification-id (var-get next-verification-id))
    )
        (map-set batch-nft-items { batch-id: batch-id, item-index: current-index } {
            contract-address: (get contract-address nft-item),
            token-id: (get token-id nft-item),
            verification-id: verification-id,
            is-completed: false
        })
        (var-set next-verification-id (+ verification-id u1))
        (+ current-index u1)
    )
)

(define-public (submit-batch-verification-item
    (batch-id uint)
    (item-index uint)
    (ai-model (string-ascii 50))
    (confidence-score uint)
    (metadata-hash (buff 32))
)
    (let (
        (verifier-data (default-to 
            { reputation-score: u0, total-verifications: u0, successful-verifications: u0, is-certified: false, certification-date: u0 }
            (map-get? verifier-credentials tx-sender)
        ))
        (model-data (unwrap! (map-get? ai-models ai-model) ERR_INVALID_AI_MODEL))
        (batch-data (unwrap! (map-get? batch-verification-requests batch-id) ERR_NOT_FOUND))
        (nft-item (unwrap! (map-get? batch-nft-items { batch-id: batch-id, item-index: item-index }) ERR_NOT_FOUND))
        (is-verified (>= confidence-score (get accuracy-threshold model-data)))
        (contract-address (get contract-address nft-item))
        (token-id (get token-id nft-item))
        (verification-id (get verification-id nft-item))
        (new-completed-count (+ (get completed-count batch-data) u1))
        (is-batch-complete (is-eq new-completed-count (get nft-count batch-data)))
        (new-status (if is-batch-complete "completed" "in-progress"))
    )
        (asserts! (get is-certified verifier-data) ERR_UNAUTHORIZED)
        (asserts! (get is-active model-data) ERR_INVALID_AI_MODEL)
        (asserts! (not (is-eq (get status batch-data) "completed")) ERR_VERIFICATION_FAILED)
        (asserts! (not (get is-completed nft-item)) ERR_ALREADY_EXISTS)
        (asserts! (and (>= confidence-score u0) (<= confidence-score u100)) ERR_INVALID_METADATA)
        (asserts! (is-none (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })) ERR_ALREADY_EXISTS)
        
        (map-set verified-nfts 
            { contract-address: contract-address, token-id: token-id }
            {
                verification-id: verification-id,
                ai-model: ai-model,
                confidence-score: confidence-score,
                verifier: tx-sender,
                timestamp: stacks-block-height,
                metadata-hash: metadata-hash,
                is-verified: is-verified
            }
        )
        
        (map-set batch-nft-items { batch-id: batch-id, item-index: item-index }
            (merge nft-item { is-completed: true })
        )
        
        (map-set batch-verification-requests batch-id 
            (merge batch-data { 
                completed-count: new-completed-count,
                status: new-status 
            })
        )
        
        (map-set verifier-credentials tx-sender {
            reputation-score: (get reputation-score verifier-data),
            total-verifications: (+ (get total-verifications verifier-data) u1),
            successful-verifications: (+ (get successful-verifications verifier-data) (if is-verified u1 u0)),
            is-certified: true,
            certification-date: (get certification-date verifier-data)
        })
        
        (ok is-verified)
    )
)

(define-public (update-batch-discount-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u50) ERR_INVALID_METADATA)
        (var-set batch-discount-rate new-rate)
        (ok true)
    )
)

(define-public (update-verification-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set verification-fee new-fee)
        (ok true)
    )
)

(define-public (deactivate-ai-model (model-id (string-ascii 50)))
    (let (
        (model-data (unwrap! (map-get? ai-models model-id) ERR_NOT_FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (map-set ai-models model-id 
            (merge model-data { is-active: false })
        ))
    )
)

(define-public (revoke-verifier-certification (verifier principal))
    (let (
        (verifier-data (unwrap! (map-get? verifier-credentials verifier) ERR_NOT_FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (map-set verifier-credentials verifier 
            (merge verifier-data { is-certified: false })
        ))
    )
)

(define-read-only (get-nft-verification (contract-address principal) (token-id uint))
    (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
)

(define-read-only (get-ai-model-info (model-id (string-ascii 50)))
    (map-get? ai-models model-id)
)

(define-read-only (get-verifier-credentials (verifier principal))
    (map-get? verifier-credentials verifier)
)

(define-read-only (get-verification-request (verification-id uint))
    (map-get? verification-requests verification-id)
)

(define-read-only (get-verification-fee)
    (var-get verification-fee)
)

(define-read-only (is-nft-ai-verified (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (get is-verified verification-data)
        false
    )
)

(define-read-only (get-verifier-reputation (verifier principal))
    (match (map-get? verifier-credentials verifier)
        verifier-data (get reputation-score verifier-data)
        u0
    )
)

(define-read-only (get-verification-confidence (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (some (get confidence-score verification-data))
        none
    )
)

(define-read-only (get-batch-verification-request (batch-id uint))
    (map-get? batch-verification-requests batch-id)
)

(define-read-only (get-batch-nft-item (batch-id uint) (item-index uint))
    (map-get? batch-nft-items { batch-id: batch-id, item-index: item-index })
)

(define-read-only (get-batch-discount-rate)
    (var-get batch-discount-rate)
)

(define-read-only (calculate-batch-fee (nft-count uint))
    (let (
        (base-fee (var-get verification-fee))
        (discount-rate (var-get batch-discount-rate))
        (discount-amount (/ (* base-fee nft-count discount-rate) u100))
        (total-fee (- (* base-fee nft-count) discount-amount))
    )
        total-fee
    )
)

(define-read-only (get-batch-progress (batch-id uint))
    (match (map-get? batch-verification-requests batch-id)
        batch-data (some {
            completed: (get completed-count batch-data),
            total: (get nft-count batch-data),
            status: (get status batch-data)
        })
        none
    )
)