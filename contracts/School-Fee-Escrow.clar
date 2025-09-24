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
(define-constant err-payment-plan-not-found (err u111))
(define-constant err-payment-plan-inactive (err u112))
(define-constant err-payment-not-due (err u113))
(define-constant err-payment-already-completed (err u114))
(define-constant err-insufficient-installments (err u115))

(define-data-var next-escrow-id uint u1)
(define-data-var next-payment-plan-id uint u1)
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

(define-map payment-plans
    uint
    {
        school: principal,
        total-amount: uint,
        installment-amount: uint,
        installment-count: uint,
        interval-blocks: uint,
        created-at: uint,
        is-active: bool,
    }
)

(define-map student-payment-subscriptions
    {
        student: principal,
        plan-id: uint,
    }
    {
        payments-made: uint,
        next-payment-due: uint,
        status: (string-ascii 20),
        subscribed-at: uint,
        last-payment-at: (optional uint),
    }
)

(define-map payment-plan-history
    principal
    (list 50 uint)
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

(define-read-only (get-next-payment-plan-id)
    (var-get next-payment-plan-id)
)

(define-read-only (get-payment-plan (plan-id uint))
    (map-get? payment-plans plan-id)
)

(define-read-only (get-payment-subscription
        (student principal)
        (plan-id uint)
    )
    (map-get? student-payment-subscriptions {
        student: student,
        plan-id: plan-id,
    })
)

(define-read-only (get-student-payment-plans (student principal))
    (default-to (list) (map-get? payment-plan-history student))
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
        (list
            u1             u2             u3             u4             u5
            u6             u7             u8             u9             u10
            u11             u12             u13             u14             u15
            u16             u17             u18             u19
            u20
        ) {
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

(define-public (create-payment-plan
        (total-amount uint)
        (installment-count uint)
        (interval-blocks uint)
    )
    (let (
            (school tx-sender)
            (plan-id (var-get next-payment-plan-id))
            (installment-amount (/ total-amount installment-count))
        )
        (asserts! (is-school-registered school) err-school-not-registered)
        (asserts! (> total-amount u0) err-invalid-amount)
        (asserts! (>= installment-count u2) err-insufficient-installments)
        (asserts! (> interval-blocks u0) err-invalid-amount)
        (asserts! (> installment-amount u0) err-invalid-amount)

        (map-set payment-plans plan-id {
            school: school,
            total-amount: total-amount,
            installment-amount: installment-amount,
            installment-count: installment-count,
            interval-blocks: interval-blocks,
            created-at: stacks-block-height,
            is-active: true,
        })

        (var-set next-payment-plan-id (+ plan-id u1))
        (ok plan-id)
    )
)

(define-public (subscribe-to-payment-plan (plan-id uint))
    (let (
            (student tx-sender)
            (plan-data (unwrap! (map-get? payment-plans plan-id) err-payment-plan-not-found))
            (subscription-key {
                student: student,
                plan-id: plan-id,
            })
        )
        (asserts! (get is-active plan-data) err-payment-plan-inactive)
        (asserts!
            (is-none (map-get? student-payment-subscriptions subscription-key))
            err-already-exists
        )

        (map-set student-payment-subscriptions subscription-key {
            payments-made: u0,
            next-payment-due: (+ stacks-block-height (get interval-blocks plan-data)),
            status: "active",
            subscribed-at: stacks-block-height,
            last-payment-at: none,
        })

        (map-set payment-plan-history student
            (unwrap-panic (as-max-len? (append (get-student-payment-plans student) plan-id) u50))
        )

        (ok true)
    )
)

(define-public (execute-payment-plan-installment
        (student principal)
        (plan-id uint)
    )
    (let (
            (plan-data (unwrap! (map-get? payment-plans plan-id) err-payment-plan-not-found))
            (subscription-key {
                student: student,
                plan-id: plan-id,
            })
            (subscription-data (unwrap! (map-get? student-payment-subscriptions subscription-key)
                err-not-found
            ))
            (installment-amount (get installment-amount plan-data))
            (platform-fee (calculate-platform-fee installment-amount))
            (total-payment (+ installment-amount platform-fee))
            (payments-made (get payments-made subscription-data))
        )
        (asserts! (is-eq (get status subscription-data) "active")
            err-payment-plan-inactive
        )
        (asserts!
            (>= stacks-block-height (get next-payment-due subscription-data))
            err-payment-not-due
        )
        (asserts! (< payments-made (get installment-count plan-data))
            err-payment-already-completed
        )
        (asserts! (>= (stx-get-balance student) total-payment)
            err-insufficient-balance
        )

        (try! (stx-transfer? total-payment student (as-contract tx-sender)))

        (let ((new-payments-made (+ payments-made u1)))
            (if (< new-payments-made (get installment-count plan-data))
                (map-set student-payment-subscriptions subscription-key
                    (merge subscription-data {
                        payments-made: new-payments-made,
                        next-payment-due: (+ stacks-block-height (get interval-blocks plan-data)),
                        last-payment-at: (some stacks-block-height),
                    })
                )
                (begin
                    (map-set student-payment-subscriptions subscription-key
                        (merge subscription-data {
                            payments-made: new-payments-made,
                            status: "completed",
                            last-payment-at: (some stacks-block-height),
                        })
                    )
                    (try! (as-contract (stx-transfer?
                        (* installment-amount (get installment-count plan-data))
                        tx-sender (get school plan-data)
                    )))
                    (try! (as-contract (stx-transfer?
                        (* platform-fee (get installment-count plan-data))
                        tx-sender contract-owner
                    )))
                )
            )
        )

        (map-set platform-stats "payment-plan-volume"
            (+ (get-platform-stat "payment-plan-volume") installment-amount)
        )
        (ok true)
    )
)

(define-public (batch-execute-due-payments (payment-list (list 10 {
    student: principal,
    plan-id: uint,
})))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (fold execute-single-payment payment-list (ok u0))
    )
)

(define-private (execute-single-payment
        (payment-info {
            student: principal,
            plan-id: uint,
        })
        (prev-result (response uint uint))
    )
    (match prev-result
        success-count (match (execute-payment-plan-installment (get student payment-info)
            (get plan-id payment-info)
        )
            payment-success (ok (+ success-count u1))
            payment-error (ok success-count)
        )
        error-val (err error-val)
    )
)

(define-public (pause-payment-subscription
        (student principal)
        (plan-id uint)
    )
    (let (
            (subscription-key {
                student: student,
                plan-id: plan-id,
            })
            (subscription-data (unwrap! (map-get? student-payment-subscriptions subscription-key)
                err-not-found
            ))
        )
        (asserts! (or (is-eq tx-sender student) (is-eq tx-sender contract-owner))
            err-unauthorized
        )
        (asserts! (is-eq (get status subscription-data) "active")
            err-payment-plan-inactive
        )

        (map-set student-payment-subscriptions subscription-key
            (merge subscription-data { status: "paused" })
        )
        (ok true)
    )
)

(define-public (resume-payment-subscription
        (student principal)
        (plan-id uint)
    )
    (let (
            (subscription-key {
                student: student,
                plan-id: plan-id,
            })
            (subscription-data (unwrap! (map-get? student-payment-subscriptions subscription-key)
                err-not-found
            ))
            (plan-data (unwrap! (map-get? payment-plans plan-id) err-payment-plan-not-found))
        )
        (asserts! (or (is-eq tx-sender student) (is-eq tx-sender contract-owner))
            err-unauthorized
        )
        (asserts! (is-eq (get status subscription-data) "paused")
            err-payment-plan-inactive
        )

        (map-set student-payment-subscriptions subscription-key
            (merge subscription-data {
                status: "active",
                next-payment-due: (+ stacks-block-height (get interval-blocks plan-data)),
            })
        )
        (ok true)
    )
)

(define-public (cancel-payment-subscription
        (student principal)
        (plan-id uint)
    )
    (let (
            (subscription-key {
                student: student,
                plan-id: plan-id,
            })
            (subscription-data (unwrap! (map-get? student-payment-subscriptions subscription-key)
                err-not-found
            ))
        )
        (asserts! (or (is-eq tx-sender student) (is-eq tx-sender contract-owner))
            err-unauthorized
        )
        (asserts! (not (is-eq (get status subscription-data) "completed"))
            err-payment-already-completed
        )

        (map-set student-payment-subscriptions subscription-key
            (merge subscription-data { status: "cancelled" })
        )
        (ok true)
    )
)

(define-public (toggle-payment-plan-status (plan-id uint))
    (let (
            (plan-data (unwrap! (map-get? payment-plans plan-id) err-payment-plan-not-found))
            (school (get school plan-data))
        )
        (asserts! (is-eq tx-sender school) err-unauthorized)

        (map-set payment-plans plan-id
            (merge plan-data { is-active: (not (get is-active plan-data)) })
        )
        (ok true)
    )
)

(define-read-only (get-payment-plan-summary (plan-id uint))
    (match (map-get? payment-plans plan-id)
        plan-data (some {
            plan-id: plan-id,
            school: (get school plan-data),
            total-amount: (get total-amount plan-data),
            installment-amount: (get installment-amount plan-data),
            installment-count: (get installment-count plan-data),
            interval-blocks: (get interval-blocks plan-data),
            is-active: (get is-active plan-data),
            created-at: (get created-at plan-data),
        })
        none
    )
)

(define-read-only (get-subscription-summary
        (student principal)
        (plan-id uint)
    )
    (match (get-payment-subscription student plan-id)
        subscription-data (match (get-payment-plan plan-id)
            plan-data (some {
                student: student,
                plan-id: plan-id,
                payments-made: (get payments-made subscription-data),
                payments-remaining: (- (get installment-count plan-data)
                    (get payments-made subscription-data)
                ),
                next-payment-due: (get next-payment-due subscription-data),
                status: (get status subscription-data),
                blocks-until-next: (if (> (get next-payment-due subscription-data)
                        stacks-block-height
                    )
                    (- (get next-payment-due subscription-data)
                        stacks-block-height
                    )
                    u0
                ),
            })
            none
        )
        none
    )
)

(define-read-only (calculate-total-plan-cost (plan-id uint))
    (match (get-payment-plan plan-id)
        plan-data (let (
                (total-amount (get total-amount plan-data))
                (installment-count (get installment-count plan-data))
                (platform-fee-per-payment (calculate-platform-fee (get installment-amount plan-data)))
                (total-platform-fees (* platform-fee-per-payment installment-count))
            )
            (some (+ total-amount total-platform-fees))
        )
        none
    )
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
            (list
                u1                 u2                 u3                 u4
                u5                 u6                 u7                 u8
                u9                 u10                 u11                 u12
                u13                 u14                 u15                 u16
                u17                 u18
                u19                 u20
            )
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
(map-set platform-stats "payment-plan-volume" u0)
