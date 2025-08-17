(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-escrow-not-active (err u105))
(define-constant err-invalid-amount (err u107))
(define-constant err-deadline-passed (err u108))
(define-constant err-deadline-not-reached (err u109))
(define-constant err-school-not-registered (err u110))

(define-data-var next-escrow-id uint u1)
(define-data-var platform-fee-rate uint u250)

(define-map escrows
    uint
    {
        student: principal,
        school: principal,
        amount: uint,
        fee-amount: uint,
        deadline: uint,
        status: (string-ascii 20),
        created-at: uint,
        released-at: (optional uint),
        refunded-at: (optional uint),
    }
)

(define-map registered-schools
    principal
    {
        name: (string-ascii 100),
        registration-fee: uint,
        is-active: bool,
        registered-at: uint,
    }
)

(define-map student-escrow-history
    principal
    (list 50 uint)
)

(define-map school-escrow-history
    principal
    (list 100 uint)
)

(define-map platform-stats
    (string-ascii 20)
    uint
)

(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrows escrow-id)
)

(define-read-only (get-registered-school (school principal))
    (map-get? registered-schools school)
)

(define-read-only (get-student-history (student principal))
    (default-to (list) (map-get? student-escrow-history student))
)

(define-read-only (get-school-history (school principal))
    (default-to (list) (map-get? school-escrow-history school))
)

(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

(define-read-only (get-next-escrow-id)
    (var-get next-escrow-id)
)

(define-read-only (get-platform-stat (stat-name (string-ascii 20)))
    (default-to u0 (map-get? platform-stats stat-name))
)

(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-read-only (is-school-registered (school principal))
    (match (map-get? registered-schools school)
        school-data (get is-active school-data)
        false
    )
)

(define-read-only (can-release-escrow (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (and
            (is-eq (get status escrow-data) "active")
            (>= stacks-block-height (get deadline escrow-data))
        )
        false
    )
)

(define-read-only (can-refund-escrow (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (and
            (is-eq (get status escrow-data) "active")
            (< stacks-block-height (get deadline escrow-data))
        )
        false
    )
)

(define-public (register-school
        (name (string-ascii 100))
        (registration-fee uint)
    )
    (let (
            (caller tx-sender)
            (current-block stacks-block-height)
        )
        (asserts! (> (len name) u0) err-invalid-amount)
        (asserts! (is-none (map-get? registered-schools caller))
            err-already-exists
        )

        (map-set registered-schools caller {
            name: name,
            registration-fee: registration-fee,
            is-active: true,
            registered-at: current-block,
        })

        (map-set platform-stats "total-schools"
            (+ (get-platform-stat "total-schools") u1)
        )
        (ok caller)
    )
)

(define-public (update-school-status
        (school principal)
        (is-active bool)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some (map-get? registered-schools school)) err-not-found)

        (map-set registered-schools school
            (merge (unwrap-panic (map-get? registered-schools school)) { is-active: is-active })
        )
        (ok true)
    )
)

(define-public (create-escrow
        (school principal)
        (fee-amount uint)
        (deadline-blocks uint)
    )
    (let (
            (student tx-sender)
            (escrow-id (var-get next-escrow-id))
            (deadline (+ stacks-block-height deadline-blocks))
            (platform-fee (calculate-platform-fee fee-amount))
            (total-amount (+ fee-amount platform-fee))
        )
        (asserts! (> fee-amount u0) err-invalid-amount)
        (asserts! (> deadline-blocks u0) err-invalid-amount)
        (asserts! (is-school-registered school) err-school-not-registered)
        (asserts! (>= (stx-get-balance student) total-amount)
            err-insufficient-balance
        )

        (try! (stx-transfer? total-amount student (as-contract tx-sender)))

        (map-set escrows escrow-id {
            student: student,
            school: school,
            amount: fee-amount,
            fee-amount: platform-fee,
            deadline: deadline,
            status: "active",
            created-at: stacks-block-height,
            released-at: none,
            refunded-at: none,
        })

        (map-set student-escrow-history student
            (unwrap-panic (as-max-len? (append (get-student-history student) escrow-id) u50))
        )

        (map-set school-escrow-history school
            (unwrap-panic (as-max-len? (append (get-school-history school) escrow-id) u100))
        )

        (map-set platform-stats "total-escrows"
            (+ (get-platform-stat "total-escrows") u1)
        )
        (map-set platform-stats "total-volume"
            (+ (get-platform-stat "total-volume") fee-amount)
        )

        (var-set next-escrow-id (+ escrow-id u1))
        (ok escrow-id)
    )
)

(define-public (release-payment (escrow-id uint))
    (let (
            (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
            (school (get school escrow-data))
            (amount (get amount escrow-data))
            (fee-amount (get fee-amount escrow-data))
        )
        (asserts! (is-eq tx-sender school) err-unauthorized)
        (asserts! (is-eq (get status escrow-data) "active") err-escrow-not-active)
        (asserts! (>= stacks-block-height (get deadline escrow-data))
            err-deadline-not-reached
        )

        (try! (as-contract (stx-transfer? amount tx-sender school)))
        (try! (as-contract (stx-transfer? fee-amount tx-sender contract-owner)))

        (map-set escrows escrow-id
            (merge escrow-data {
                status: "released",
                released-at: (some stacks-block-height),
            })
        )

        (map-set platform-stats "total-released"
            (+ (get-platform-stat "total-released") u1)
        )
        (ok true)
    )
)

(define-public (refund-payment (escrow-id uint))
    (let (
            (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
            (student (get student escrow-data))
            (amount (get amount escrow-data))
            (fee-amount (get fee-amount escrow-data))
            (total-refund (+ amount fee-amount))
        )
        (asserts! (or (is-eq tx-sender student) (is-eq tx-sender contract-owner))
            err-unauthorized
        )
        (asserts! (is-eq (get status escrow-data) "active") err-escrow-not-active)
        (asserts! (< stacks-block-height (get deadline escrow-data))
            err-deadline-passed
        )

        (try! (as-contract (stx-transfer? total-refund tx-sender student)))

        (map-set escrows escrow-id
            (merge escrow-data {
                status: "refunded",
                refunded-at: (some stacks-block-height),
            })
        )

        (map-set platform-stats "total-refunded"
            (+ (get-platform-stat "total-refunded") u1)
        )
        (ok true)
    )
)

(define-public (emergency-refund (escrow-id uint))
    (let (
            (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
            (student (get student escrow-data))
            (amount (get amount escrow-data))
            (fee-amount (get fee-amount escrow-data))
            (total-refund (+ amount fee-amount))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status escrow-data) "active") err-escrow-not-active)

        (try! (as-contract (stx-transfer? total-refund tx-sender student)))

        (map-set escrows escrow-id
            (merge escrow-data {
                status: "emergency-refunded",
                refunded-at: (some stacks-block-height),
            })
        )

        (map-set platform-stats "emergency-refunds"
            (+ (get-platform-stat "emergency-refunds") u1)
        )
        (ok true)
    )
)

(define-public (update-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-rate u1000) err-invalid-amount)
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

(define-read-only (get-escrow-summary (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (some {
            escrow-id: escrow-id,
            student: (get student escrow-data),
            school: (get school escrow-data),
            amount: (get amount escrow-data),
            status: (get status escrow-data),
            deadline: (get deadline escrow-data),
            blocks-remaining: (if (>= (get deadline escrow-data) stacks-block-height)
                (- (get deadline escrow-data) stacks-block-height)
                u0
            ),
        })
        none
    )
)

(define-read-only (get-active-escrows-for-school (school principal))
    (filter is-active-escrow (get-school-history school))
)

(define-read-only (get-active-escrows-for-student (student principal))
    (filter is-active-escrow (get-student-history student))
)

(define-private (is-active-escrow (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (is-eq (get status escrow-data) "active")
        false
    )
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-public (withdraw-platform-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount (get-contract-balance)) err-insufficient-balance)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (ok true)
    )
)

(define-public (extend-escrow-deadline
        (escrow-id uint)
        (additional-blocks uint)
    )
    (let (
            (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
            (new-deadline (+ (get deadline escrow-data) additional-blocks))
        )
        (asserts!
            (or (is-eq tx-sender (get student escrow-data)) (is-eq tx-sender (get school escrow-data)))
            err-unauthorized
        )
        (asserts! (is-eq (get status escrow-data) "active") err-escrow-not-active)
        (asserts! (> additional-blocks u0) err-invalid-amount)

        (map-set escrows escrow-id (merge escrow-data { deadline: new-deadline }))
        (ok new-deadline)
    )
)

(define-public (dispute-escrow
        (escrow-id uint)
        (reason (string-ascii 200))
    )
    (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
        (asserts!
            (or (is-eq tx-sender (get student escrow-data)) (is-eq tx-sender (get school escrow-data)))
            err-unauthorized
        )
        (asserts! (is-eq (get status escrow-data) "active") err-escrow-not-active)
        (asserts! (> (len reason) u0) err-invalid-amount)

        (map-set escrows escrow-id (merge escrow-data { status: "disputed" }))

        (map-set platform-stats "total-disputes"
            (+ (get-platform-stat "total-disputes") u1)
        )
        (ok true)
    )
)

(define-public (resolve-dispute
        (escrow-id uint)
        (resolution (string-ascii 20))
    )
    (let ((escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status escrow-data) "disputed")
            err-escrow-not-active
        )
        (asserts! (or (is-eq resolution "release") (is-eq resolution "refund"))
            err-invalid-amount
        )

        (if (is-eq resolution "release")
            (begin
                (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender
                    (get school escrow-data)
                )))
                (try! (as-contract (stx-transfer? (get fee-amount escrow-data) tx-sender
                    contract-owner
                )))
                (map-set escrows escrow-id
                    (merge escrow-data {
                        status: "released",
                        released-at: (some stacks-block-height),
                    })
                )
            )
            (begin
                (try! (as-contract (stx-transfer?
                    (+ (get amount escrow-data) (get fee-amount escrow-data))
                    tx-sender (get student escrow-data)
                )))
                (map-set escrows escrow-id
                    (merge escrow-data {
                        status: "refunded",
                        refunded-at: (some stacks-block-height),
                    })
                )
            )
        )
        (ok true)
    )
)

(define-read-only (get-escrow-by-student-and-school
        (student principal)
        (school principal)
    )
    (fold find-matching-escrow (get-student-history student) none)
)

(define-private (find-matching-escrow
        (escrow-id uint)
        (prev (optional uint))
    )
    (match prev
        found-id (some found-id)
        (match (map-get? escrows escrow-id)
            escrow-data (if (is-eq (get school escrow-data) tx-sender)
                (some escrow-id)
                none
            )
            none
        )
    )
)

(define-read-only (get-total-escrows-by-status (status (string-ascii 20)))
    (fold count-status-escrows
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
            u20) {
        target-status: status,
        count: u0,
    })
)

(define-private (count-status-escrows
        (escrow-id uint)
        (data {
            target-status: (string-ascii 20),
            count: uint,
        })
    )
    (match (map-get? escrows escrow-id)
        escrow-data (if (is-eq (get status escrow-data) (get target-status data))
            {
                target-status: (get target-status data),
                count: (+ (get count data) u1),
            }
            data
        )
        data
    )
)

(define-read-only (get-platform-summary)
    {
        total-schools: (get-platform-stat "total-schools"),
        total-escrows: (get-platform-stat "total-escrows"),
        total-volume: (get-platform-stat "total-volume"),
        total-released: (get-platform-stat "total-released"),
        total-refunded: (get-platform-stat "total-refunded"),
        total-disputes: (get-platform-stat "total-disputes"),
        contract-balance: (get-contract-balance),
        platform-fee-rate: (var-get platform-fee-rate),
        current-block: stacks-block-height,
    }
)

(define-public (update-school-registration-fee (new-fee uint))
    (let (
            (school tx-sender)
            (school-data (unwrap! (map-get? registered-schools school) err-not-found))
        )
        (asserts! (get is-active school-data) err-unauthorized)

        (map-set registered-schools school
            (merge school-data { registration-fee: new-fee })
        )
        (ok true)
    )
)

(define-public (get-escrow-status (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (ok {
            status: (get status escrow-data),
            can-release: (can-release-escrow escrow-id),
            can-refund: (can-refund-escrow escrow-id),
            deadline: (get deadline escrow-data),
            current-block: stacks-block-height,
        })
        err-not-found
    )
)

(define-public (mass-refund-expired-escrows)
    (let ((caller tx-sender))
        (asserts! (is-eq caller contract-owner) err-owner-only)
        (fold refund-if-expired
            (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18
                u19 u20)
            (ok u0)
        )
    )
)

(define-private (refund-if-expired
        (escrow-id uint)
        (prev-result (response uint uint))
    )
    (match prev-result
        success-count (match (map-get? escrows escrow-id)
            escrow-data (if (and
                    (is-eq (get status escrow-data) "active")
                    (< stacks-block-height (get deadline escrow-data))
                )
                (begin
                    (match (as-contract (stx-transfer?
                        (+ (get amount escrow-data) (get fee-amount escrow-data))
                        tx-sender (get student escrow-data)
                    ))
                        transfer-success (begin
                            (map-set escrows escrow-id
                                (merge escrow-data {
                                    status: "auto-refunded",
                                    refunded-at: (some stacks-block-height),
                                })
                            )
                            (ok (+ success-count u1))
                        )
                        transfer-error (ok success-count)
                    )
                )
                (ok success-count)
            )
            (ok success-count)
        )
        error-val (err error-val)
    )
)

(define-read-only (get-school-earnings (school principal))
    (fold calculate-school-earnings (get-school-history school) u0)
)

(define-private (calculate-school-earnings
        (escrow-id uint)
        (total uint)
    )
    (match (map-get? escrows escrow-id)
        escrow-data (if (is-eq (get status escrow-data) "released")
            (+ total (get amount escrow-data))
            total
        )
        total
    )
)

(define-read-only (get-student-total-paid (student principal))
    (fold calculate-student-payments (get-student-history student) u0)
)

(define-private (calculate-student-payments
        (escrow-id uint)
        (total uint)
    )
    (match (map-get? escrows escrow-id)
        escrow-data (if (is-eq (get status escrow-data) "released")
            (+ total (+ (get amount escrow-data) (get fee-amount escrow-data)))
            total
        )
        total
    )
)

(map-set platform-stats "total-schools" u0)
(map-set platform-stats "total-escrows" u0)
(map-set platform-stats "total-volume" u0)
(map-set platform-stats "total-released" u0)
(map-set platform-stats "total-refunded" u0)
(map-set platform-stats "total-disputes" u0)
