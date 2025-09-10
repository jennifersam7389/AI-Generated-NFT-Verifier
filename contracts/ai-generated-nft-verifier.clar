(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_METADATA (err u103))
(define-constant ERR_VERIFICATION_FAILED (err u104))
(define-constant ERR_INVALID_AI_MODEL (err u105))
(define-constant ERR_DISPUTE_EXPIRED (err u106))
(define-constant ERR_INSUFFICIENT_BOND (err u107))

(define-data-var next-verification-id uint u1)
(define-data-var verification-fee uint u1000000)
(define-data-var next-batch-id uint u1)
(define-data-var batch-discount-rate uint u10)
(define-data-var verification-expiry-period uint u52560)
(define-data-var renewal-fee uint u500000)
(define-data-var next-renewal-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var dispute-bond uint u2000000)
(define-data-var dispute-period uint u1440)

(define-map verified-nfts
    { contract-address: principal, token-id: uint }
    {
        verification-id: uint,
        ai-model: (string-ascii 50),
        confidence-score: uint,
        verifier: principal,
        timestamp: uint,
        metadata-hash: (buff 32),
        is-verified: bool,
        expiry-block: uint,
        renewal-count: uint
    }
)

(define-map verification-renewals
    uint
    {
        contract-address: principal,
        token-id: uint,
        original-verification-id: uint,
        renewed-by: principal,
        renewal-timestamp: uint,
        new-expiry-block: uint,
        renewal-fee-paid: uint
    }
)

(define-map verification-disputes
    uint
    {
        contract-address: principal,
        token-id: uint,
        verification-id: uint,
        disputer: principal,
        evidence-hash: (buff 32),
        dispute-reason: (string-ascii 200),
        bond-amount: uint,
        dispute-timestamp: uint,
        status: (string-ascii 20),
        resolution-timestamp: uint,
        resolved-by: principal
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
                is-verified: is-verified,
                expiry-block: (+ stacks-block-height (var-get verification-expiry-period)),
                renewal-count: u0
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
                is-verified: is-verified,
                expiry-block: (+ stacks-block-height (var-get verification-expiry-period)),
                renewal-count: u0
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

(define-public (renew-verification (contract-address principal) (token-id uint))
    (let (
        (verification-data (unwrap! (map-get? verified-nfts { contract-address: contract-address, token-id: token-id }) ERR_NOT_FOUND))
        (renewal-id (var-get next-renewal-id))
        (renewal-fee-amount (var-get renewal-fee))
        (current-block stacks-block-height)
        (new-expiry (+ current-block (var-get verification-expiry-period)))
        (current-renewal-count (get renewal-count verification-data))
    )
        (asserts! (>= current-block (get expiry-block verification-data)) ERR_VERIFICATION_FAILED)
        (try! (stx-transfer? renewal-fee-amount tx-sender (as-contract tx-sender)))
        (map-set verification-renewals renewal-id {
            contract-address: contract-address,
            token-id: token-id,
            original-verification-id: (get verification-id verification-data),
            renewed-by: tx-sender,
            renewal-timestamp: current-block,
            new-expiry-block: new-expiry,
            renewal-fee-paid: renewal-fee-amount
        })
        (map-set verified-nfts { contract-address: contract-address, token-id: token-id }
            (merge verification-data { 
                expiry-block: new-expiry,
                renewal-count: (+ current-renewal-count u1)
            })
        )
        (var-set next-renewal-id (+ renewal-id u1))
        (ok renewal-id)
    )
)

(define-public (update-expiry-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (and (>= new-period u1440) (<= new-period u525600)) ERR_INVALID_METADATA)
        (var-set verification-expiry-period new-period)
        (ok true)
    )
)

(define-public (update-renewal-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set renewal-fee new-fee)
        (ok true)
    )
)

(define-public (submit-verification-dispute (contract-address principal) (token-id uint) (evidence-hash (buff 32)) (dispute-reason (string-ascii 200)))
    (let (
        (verification-data (unwrap! (map-get? verified-nfts { contract-address: contract-address, token-id: token-id }) ERR_NOT_FOUND))
        (dispute-id (var-get next-dispute-id))
        (bond-amount (var-get dispute-bond))
        (dispute-deadline (+ (get timestamp verification-data) (var-get dispute-period)))
        (current-block stacks-block-height)
    )
        (asserts! (get is-verified verification-data) ERR_VERIFICATION_FAILED)
        (asserts! (<= current-block dispute-deadline) ERR_DISPUTE_EXPIRED)
        (asserts! (not (is-eq tx-sender (get verifier verification-data))) ERR_UNAUTHORIZED)
        (try! (stx-transfer? bond-amount tx-sender (as-contract tx-sender)))
        (map-set verification-disputes dispute-id {
            contract-address: contract-address,
            token-id: token-id,
            verification-id: (get verification-id verification-data),
            disputer: tx-sender,
            evidence-hash: evidence-hash,
            dispute-reason: dispute-reason,
            bond-amount: bond-amount,
            dispute-timestamp: current-block,
            status: "pending",
            resolution-timestamp: u0,
            resolved-by: (as-contract tx-sender)
        })
        (var-set next-dispute-id (+ dispute-id u1))
        (ok dispute-id)
    )
)

(define-public (resolve-dispute (dispute-id uint) (is-dispute-valid bool))
    (let (
        (dispute-data (unwrap! (map-get? verification-disputes dispute-id) ERR_NOT_FOUND))
        (verification-data (unwrap! (map-get? verified-nfts { contract-address: (get contract-address dispute-data), token-id: (get token-id dispute-data) }) ERR_NOT_FOUND))
        (verifier-data (default-to 
            { reputation-score: u0, total-verifications: u0, successful-verifications: u0, is-certified: false, certification-date: u0 }
            (map-get? verifier-credentials (get verifier verification-data))
        ))
        (disputer (get disputer dispute-data))
        (bond-amount (get bond-amount dispute-data))
        (verifier (get verifier verification-data))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status dispute-data) "pending") ERR_VERIFICATION_FAILED)
        (if is-dispute-valid
            (begin
                (try! (as-contract (stx-transfer? bond-amount tx-sender disputer)))
                (map-set verified-nfts { contract-address: (get contract-address dispute-data), token-id: (get token-id dispute-data) }
                    (merge verification-data { is-verified: false })
                )
                (map-set verifier-credentials verifier {
                    reputation-score: (if (>= (get reputation-score verifier-data) u10) (- (get reputation-score verifier-data) u10) u0),
                    total-verifications: (get total-verifications verifier-data),
                    successful-verifications: (get successful-verifications verifier-data),
                    is-certified: (get is-certified verifier-data),
                    certification-date: (get certification-date verifier-data)
                })
                (map-set verification-disputes dispute-id 
                    (merge dispute-data { 
                        status: "upheld",
                        resolution-timestamp: stacks-block-height,
                        resolved-by: tx-sender
                    })
                )
            )
            (begin
                (map-set verification-disputes dispute-id 
                    (merge dispute-data { 
                        status: "rejected",
                        resolution-timestamp: stacks-block-height,
                        resolved-by: tx-sender
                    })
                )
                (map-set verifier-credentials verifier {
                    reputation-score: (+ (get reputation-score verifier-data) u5),
                    total-verifications: (get total-verifications verifier-data),
                    successful-verifications: (get successful-verifications verifier-data),
                    is-certified: (get is-certified verifier-data),
                    certification-date: (get certification-date verifier-data)
                })
            )
        )
        (ok is-dispute-valid)
    )
)

(define-public (update-dispute-bond (new-bond uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set dispute-bond new-bond)
        (ok true)
    )
)

(define-public (update-dispute-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (and (>= new-period u144) (<= new-period u10080)) ERR_INVALID_METADATA)
        (var-set dispute-period new-period)
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

(define-read-only (is-verification-expired (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (>= stacks-block-height (get expiry-block verification-data))
        true
    )
)

(define-read-only (get-verification-expiry (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (some (get expiry-block verification-data))
        none
    )
)

(define-read-only (get-renewal-history (renewal-id uint))
    (map-get? verification-renewals renewal-id)
)

(define-read-only (get-verification-renewal-count (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (get renewal-count verification-data)
        u0
    )
)

(define-read-only (get-expiry-period)
    (var-get verification-expiry-period)
)

(define-read-only (get-renewal-fee)
    (var-get renewal-fee)
)

(define-read-only (is-verification-current (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (and 
            (get is-verified verification-data)
            (< stacks-block-height (get expiry-block verification-data))
        )
        false
    )
)

(define-read-only (get-dispute-info (dispute-id uint))
    (map-get? verification-disputes dispute-id)
)

(define-read-only (is-dispute-period-active (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (<= stacks-block-height (+ (get timestamp verification-data) (var-get dispute-period)))
        false
    )
)

(define-read-only (get-dispute-bond)
    (var-get dispute-bond)
)

(define-read-only (get-dispute-period)
    (var-get dispute-period)
)

(define-read-only (can-submit-dispute (contract-address principal) (token-id uint) (potential-disputer principal))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (and
            (get is-verified verification-data)
            (<= stacks-block-height (+ (get timestamp verification-data) (var-get dispute-period)))
            (not (is-eq potential-disputer (get verifier verification-data)))
        )
        false
    )
)

(define-read-only (get-dispute-deadline (contract-address principal) (token-id uint))
    (match (map-get? verified-nfts { contract-address: contract-address, token-id: token-id })
        verification-data (some (+ (get timestamp verification-data) (var-get dispute-period)))
        none
    )
)