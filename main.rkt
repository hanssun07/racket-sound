#lang racket/base

(require
    (for-syntax racket/base)
    racket/match racket/pretty racket/list racket/math
    rsound rsound/piano-tones
    gregor)

(define-syntax-rule
    (define-match-pattern (a . b) c)
    (define-match-expander a
        (lambda (stx) (syntax-case stx () [(_ . b) #'c]))))
(define-match-pattern (datetime/m y M d h m s ns)
    (and (? datetime-provider?)
         (app ->year        y)
         (app ->month       M)
         (app ->day         d)
         (app ->hours       h)
         (app ->minutes     m)
         (app ->seconds     s)
         (app ->nanoseconds ns)))

(define (5min-block-of [dt (now)])
    (match-define (datetime/m y M d h m _ _) dt)
    (datetime y M d h (- m (remainder m 5)) 0 0))
(define (next-5min-datetime [dt (now)])
    (+minutes (5min-block-of dt) 5))

(define (time->pitch-offsets [dt (now)])
    (define dtb (5min-block-of dt))
    (match-define (datetime/m _ _ _ H+ M+ _ _) dtb)
    (match-define (datetime/m _ _ _ H- M- _ _) (-minutes (5min-block-of dtb) 5))
    (define h+ (let ([k (remainder H+ 12)]) (if (zero? k) 12 k)))
    (define h- (let ([k (remainder H- 12)]) (if (zero? k) 12 k)))
    (define m+ (quotient M+ 5))
    (if (zero? m+)
        (list (list h- 12) (list h+ m+))
        (list (list h+ m+))))

(define current-bpm (make-parameter 60))
(define (beat-frames) (* 60 (/ (default-sample-rate) (current-bpm))))
(beat-frames)

(define (b->f d) (floor (* d (beat-frames))))
(define (rs-splice sound start-beat end-beat)
    (clip sound
          (max (rsound-start sound) (b->f start-beat))
          (min (rsound-stop sound)  (b->f end-beat))))
#| for smooth clipping
(define k 1.0) (for ([i (rsound-stop p)])
    (when (> i 44100)
      (set! k (* k #i0.999))
      (s16vector-set! (~> p rsound-data) (* i 2) (exact-truncate (* k (s16vector-ref (~> p rsound-data) (* i 2)))))
      (s16vector-set! (~> p rsound-data) (add1 (* i 2)) (exact-truncate (* k (s16vector-ref (~> p rsound-data) (add1
(* i 2))))))))
|#
(define r-rest (silence 1))
(define (dbg k) (pretty-print k) k)
(define (melody-splice spec)
    (if (empty? spec)
        (silence 1)
        (match-let ([`((,starts ,notes) ...) spec])
            (assemble (for/list ([start starts] [end `(,@(cdr starts) +inf.0)] [note notes])
                       (define sound (if note (piano-tone (+ 60 note)) r-rest))
                       (list (rs-splice sound 0 (- end start))
                             (b->f start)))))))
        
(define (time->sound [dt (now)])
    (define rposs (time->pitch-offsets dt))
    (define part-specs (for/list ([offsets rposs])
        (define notes (apply append (for/list ([offset offsets]) (list 0 offset))))
        (define spec (for/list ([o notes] [i (in-naturals)]) (list i o)))
        spec))
    (define all-parts (append part-specs part-specs))
    (define post-spec (apply append (for/list ([spec all-parts] [i (in-naturals 1)])
        (map (match-lambda [`(,a ,b) (list (+ (* 6 i) a) b)]) spec))))
    (define spec `(
        (0   0)
        (1.5 5)
        (2.5 0)
        (3   5)
        ,@post-spec))
    (displayln spec)
    (define tone (parameterize ([current-bpm 240]) (melody-splice spec)))
    tone)
(define pstream (make-pstream #:buffer-time 0.9))
(define (play-time-notif [dt (now)])
    (define tone (time->sound dt))
    (collect-garbage)
    (pstream-play pstream tone))
    
(let loop ([last-block (now)])
    (define this-block (5min-block-of))
    (displayln (list last-block this-block))
    (unless (datetime=? last-block this-block)
        (play-time-notif))
    (sleep 10)
    (loop this-block))
