;; Protect Shield - shield-nft
;; A comprehensive smart contract for secure digital asset protection and generation on the Stacks blockchain.
;; This contract provides a robust framework for creating, minting, and trading unique tokenized assets
;; with advanced security features, provenance tracking, and decentralized ownership management.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-LISTED (err u101))
(define-constant ERR-NOT-LISTED (err u102))
(define-constant ERR-LISTING-EXPIRED (err u103))
(define-constant ERR-INVALID-PRICE (err u104))
(define-constant ERR-NFT-NOT-FOUND (err u105))
(define-constant ERR-DUPLICATE-PATTERN (err u106))
(define-constant ERR-INVALID-PARAMETERS (err u107))
(define-constant ERR-INSUFFICIENT-FUNDS (err u108))
(define-constant ERR-TRANSFER-FAILED (err u109))
(define-constant ERR-NOT-OWNER (err u110))

;; SIP-009 NFT Interface
(define-trait nft-trait
  (
    ;; Transfer token to a specified principal
    (transfer (uint principal principal) (response bool uint))
    ;; Get the token owner
    (get-owner (uint) (response principal uint))
    ;; Get the last token ID
    (get-last-token-id () (response uint uint))
    ;; Get the token URI
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
  )
)

;; Data variables
(define-data-var last-token-id uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var royalty-percentage uint u50) ;; 5.0% (represented as 50 for 5.0%)
(define-data-var mint-price uint u10000000) ;; 10 STX

;; NFT ownership tracking
(define-map token-owners uint principal)

;; Lattice pattern parameters storage
(define-map lattice-parameters 
  uint
  {
    seed: uint,                ;; Random seed for pattern generation
    lattice-type: (string-utf8 20),  ;; Type of lattice (e.g., "square", "hexagonal", "triangular")
    dimensions: {              ;; Pattern dimensions
      width: uint,
      height: uint
    },
    complexity: uint,          ;; Complexity parameter (affects number of nodes/connections)
    color-scheme: {            ;; Color scheme information
      primary: (string-utf8 20),
      secondary: (string-utf8 20),
      background: (string-utf8 20)
    },
    metadata-uri: (string-ascii 256) ;; URI for off-chain metadata/image
  }
)

;; Uniqueness verification - hash of parameters to token ID
(define-map pattern-hashes (buff 32) uint)

;; Track original creator for royalties
(define-map token-creators uint principal)

;; Marketplace listings
(define-map token-listings
  uint
  {
    price: uint,
    seller: principal,
    expiry: uint
  }
)

;; Private functions

;; Calculate hash of lattice parameters to ensure uniqueness
(define-private (hash-lattice-params
  (seed uint)
  (lattice-type (string-utf8 20))
  (width uint)
  (height uint)
  (complexity uint)
  (primary (string-utf8 20))
  (secondary (string-utf8 20))
  (background (string-utf8 20)))
  ;; Hash each parameter individually, concatenate the resulting hash buffers pairwise, then hash the result
  (sha256 
    (concat (sha256 seed) ;; H1
      (concat (sha256 (to-consensus-buff lattice-type)) ;; H2
        (concat (sha256 width) ;; H3
          (concat (sha256 height) ;; H4
            (concat (sha256 complexity) ;; H5
              (concat (sha256 (to-consensus-buff primary)) ;; H6
                (concat (sha256 (to-consensus-buff secondary)) (sha256 (to-consensus-buff background))) ;; H7 + H8 -> B1
              ) ;; H6 + B1 -> B2
            ) ;; H5 + B2 -> B3
          ) ;; H4 + B3 -> B4
        ) ;; H3 + B4 -> B5
      ) ;; H2 + B5 -> B6
    ) ;; H1 + B6 -> Final Buffer to Hash
  )
)

;; Generate a new token ID
(define-private (generate-new-token-id)
  (let ((new-id (+ (var-get last-token-id) u1)))
    (var-set last-token-id new-id)
    new-id
  )
)

;; Validate lattice parameters
(define-private (validate-lattice-params
  (seed uint)
  (lattice-type (string-utf8 20))
  (width uint)
  (height uint)
  (complexity uint)
  (primary (string-utf8 20))
  (secondary (string-utf8 20))
  (background (string-utf8 20)))
  (and
    (> width u0)
    (> height u0)
    (> complexity u0)
    (not (is-eq lattice-type ""))
    (not (is-eq primary ""))
    (not (is-eq secondary ""))
    (not (is-eq background ""))
  )
)

;; Calculate royalty amount based on sale price
(define-private (calculate-royalty (sale-price uint))
  (/ (* sale-price (var-get royalty-percentage)) u1000)
)

;; Check if caller is the owner of the token
(define-private (is-owner (token-id uint) (caller principal))
  (match (map-get? token-owners token-id)
    owner (is-eq owner caller)
    false
  )
)

;; Transfer funds to a recipient
(define-private (transfer-funds (amount uint) (recipient principal))
  (stx-transfer? amount tx-sender recipient)
)

;; Public functions

;; Mint a new lattice NFT
(define-public (mint-shield-asset
  (seed uint)
  (lattice-type (string-utf8 20))
  (width uint)
  (height uint)
  (complexity uint)
  (primary (string-utf8 20))
  (secondary (string-utf8 20))
  (background (string-utf8 20))
  (metadata-uri (string-ascii 256)))
  (let
    (
      (params-hash (hash-lattice-params seed lattice-type width height complexity primary secondary background))
      (is-valid (validate-lattice-params seed lattice-type width height complexity primary secondary background))
      (caller tx-sender)
    )
    (asserts! is-valid ERR-INVALID-PARAMETERS)
    
    ;; Check for duplicates
    (asserts! (is-none (map-get? pattern-hashes params-hash)) ERR-DUPLICATE-PATTERN)
    
    ;; Check payment
    (asserts! (is-ok (stx-transfer? (var-get mint-price) caller (var-get contract-owner))) ERR-INSUFFICIENT-FUNDS)
    
    ;; Generate new token
    (let ((token-id (generate-new-token-id)))
      ;; Save parameters
      (map-set lattice-parameters token-id {
        seed: seed,
        lattice-type: lattice-type,
        dimensions: {
          width: width,
          height: height
        },
        complexity: complexity,
        color-scheme: {
          primary: primary,
          secondary: secondary,
          background: background
        },
        metadata-uri: metadata-uri
      })
      
      ;; Set ownership and creator
      (map-set token-owners token-id caller)
      (map-set token-creators token-id caller)
      
      ;; Record pattern hash to prevent duplicates
      (map-set pattern-hashes params-hash token-id)
      
      (ok token-id)
    )
  )
)

;; Transfer ownership of an NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-owner token-id sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    ;; Remove from listing if it's listed
    (match (map-get? token-listings token-id)
      listing (map-delete token-listings token-id)
      true
    )
    ;; Update ownership
    (map-set token-owners token-id recipient)
    (ok true)
  )
)

;; List an NFT for sale
(define-public (list-for-sale (token-id uint) (price uint) (expiry uint))
  (let ((caller tx-sender))
    (asserts! (is-owner token-id caller) ERR-NOT-OWNER)
    (asserts! (> price u0) ERR-INVALID-PRICE)
    (asserts! (> expiry block-height) ERR-LISTING-EXPIRED)
    
    (map-set token-listings token-id {
      price: price,
      seller: caller,
      expiry: expiry
    })
    
    (ok true)
  )
)

;; Cancel a listing
(define-public (cancel-listing (token-id uint))
  (let ((caller tx-sender))
    (match (map-get? token-listings token-id)
      listing
        (begin
          (asserts! (is-eq (get seller listing) caller) ERR-NOT-AUTHORIZED)
          (map-delete token-listings token-id)
          (ok true)
        )
      (err ERR-NOT-LISTED)
    )
  )
)

;; Purchase a listed NFT
(define-public (purchase (token-id uint))
  (let
    (
      (buyer tx-sender)
    )
    (match (map-get? token-listings token-id)
      listing
        (let
          (
            (seller (get seller listing))
            (price (get price listing))
            (expiry (get expiry listing))
            (creator (unwrap! (map-get? token-creators token-id) ERR-NFT-NOT-FOUND))
            (royalty-amount (calculate-royalty price))
            (seller-amount (- price royalty-amount))
          )
          (asserts! (<= block-height expiry) ERR-LISTING-EXPIRED)
          
          ;; Transfer funds to creator (royalty)
          (asserts! (is-ok (stx-transfer? royalty-amount buyer creator)) ERR-TRANSFER-FAILED)
          
          ;; Transfer funds to seller
          (asserts! (is-ok (stx-transfer? seller-amount buyer seller)) ERR-TRANSFER-FAILED)
          
          ;; Transfer NFT to buyer
          (map-set token-owners token-id buyer)
          
          ;; Remove listing
          (map-delete token-listings token-id)
          
          (ok true)
        )
      (err ERR-NOT-LISTED)
    )
  )
)

;; Read-only functions

;; Get the owner of a token
(define-read-only (get-owner (token-id uint))
  (match (map-get? token-owners token-id)
    owner (ok owner)
    (err ERR-NFT-NOT-FOUND)
  )
)

;; Get the metadata URI for a token
(define-read-only (get-token-uri (token-id uint))
  (match (map-get? lattice-parameters token-id)
    params (ok (some (get metadata-uri params)))
    (err ERR-NFT-NOT-FOUND)
  )
)

;; Get the last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; Get the creator of a token
(define-read-only (get-token-creator (token-id uint))
  (match (map-get? token-creators token-id)
    creator (ok creator)
    (err ERR-NFT-NOT-FOUND)
  )
)

;; Get the lattice parameters for a token
(define-read-only (get-lattice-parameters (token-id uint))
  (match (map-get? lattice-parameters token-id)
    params (ok params)
    (err ERR-NFT-NOT-FOUND)
  )
)

;; Check if a listing exists and is valid
(define-read-only (get-listing (token-id uint))
  (match (map-get? token-listings token-id)
    listing
      (if (<= block-height (get expiry listing))
        (ok listing)
        (err ERR-LISTING-EXPIRED)
      )
    (err ERR-NOT-LISTED)
  )
)

;; Check if a pattern already exists
(define-read-only (pattern-exists 
  (seed uint)
  (lattice-type (string-utf8 20))
  (width uint)
  (height uint)
  (complexity uint)
  (primary (string-utf8 20))
  (secondary (string-utf8 20))
  (background (string-utf8 20)))
  (let ((params-hash (hash-lattice-params seed lattice-type width height complexity primary secondary background)))
    (is-some (map-get? pattern-hashes params-hash))
  )
)

;; Contract administration functions

;; Update the mint price
(define-public (set-mint-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set mint-price new-price)
    (ok true)
  )
)

;; Update the royalty percentage
(define-public (set-royalty-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-percentage u300) ERR-INVALID-PARAMETERS) ;; Max 30%
    (var-set royalty-percentage new-percentage)
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)