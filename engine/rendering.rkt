#lang racket

(provide lux-start
         final-state
         precompiler-entity
         (rename-out [make-precompiler precompiler])
         precompiler?)

(require racket/match
         racket/fixnum
         racket/flonum
         lux
         lux/chaos/gui
         lux/chaos/gui/val
         (prefix-in lux: lux/chaos/gui/key)
         (prefix-in lux: lux/chaos/gui/mouse)

         (prefix-in ml: mode-lambda)
         (prefix-in ml: mode-lambda/static)
         (prefix-in gl: mode-lambda/backend/gl))

(require "./core.rkt")
(require "../components/animated-sprite.rkt")

(struct precompiler (sprites) #:transparent)

(define (make-precompiler . animated-sprites-or-images)
  (define entities (filter entity? (flatten animated-sprites-or-images)))

  
  
  (define animated-sprites (flatten
                            (append
                             (map (lambda(e) (get-component e animated-sprite?)) entities)
                             (filter animated-sprite? (flatten animated-sprites-or-images)))))
  
  (define images (filter image? (flatten animated-sprites-or-images)))
  
  (precompiler (flatten
                (append (map fast-image images)
                        (map vector->list (map animated-sprite-frames (flatten animated-sprites)))))))


(define (lux-start larger-state)
  (define render-tick (get-mode-lambda-render-tick (game-entities larger-state)))

  (call-with-chaos
   (get-gui)
   (λ () (fiat-lux (demo larger-state render-tick)))))





(define (get-mode-lambda-render-tick original-entities)
  ;Assume the last entity is the background entity
  (define bg-entity (last original-entities))

  ;Use the background to setup some helpful constants
  (define W (w bg-entity))
  (define H (h bg-entity))
  (define W/2 (/ W 2))
  (define H/2 (/ H 2))

  ;Initialize the compiled sprite database
  (register-sprites-from-entities! original-entities)

  ;Use the entities, plus their sprites, to determine the initial sprite database
  (set! csd (entities->compiled-sprite-database original-entities))

  ;Define that we'll have one layer of sprites (for now).
  ;Fix its position at the center of the screen
  (define layers (vector (ml:layer (real->double-flonum W/2)
                                   (real->double-flonum H/2))
                         (ml:layer (real->double-flonum W/2)
                                   (real->double-flonum H/2))
                         (ml:layer (real->double-flonum W/2)
                                   (real->double-flonum H/2))))

  ;Set up our open gl render function with the current sprite database
  (define ml:render (gl:stage-draw/dc csd W H 8))
  
  (define (ticky-tick current-entities)
    
    ;Find uncompiled entities...
    (register-sprites-from-entities! current-entities)

    ;Recompile the database if we added anything:
    (thread (thunk
             (and (recompile!)
                  (set! ml:render (gl:stage-draw/dc csd W H 8)))))
    

    ;Create our sprites
    (define dynamic-sprites (game->mode-lambda-sprite-list current-entities))

    (define static-sprites '())

    ;Actually render them
    (ml:render layers dynamic-sprites static-sprites))

  ticky-tick)

(define g/v (make-gui/val))
(struct demo
  ( state render-tick)
  #:methods gen:word
  [(define (word-fps w)
     60.0)  ;Changed from 60 to 30, which makes it more smooth on the Chromebooks we use in class.
            ;   Not sure why we were seeing such dramatic framerate drops
   
   (define (word-label s ft)
     (lux-standard-label "Values" ft))
   
   (define (word-output w)
     (match-define (demo  state render-tick) w)

     (get-render render-tick))
   
   (define (word-event w e)
     (match-define (demo  state render-tick) w)
     (define closed? #f)
     (cond
       [(eq? e 'close)  #f]
       [(lux:key-event? e)

       
        (if (not (eq? 'release (send e get-key-code)))
            (demo  (handle-key-down state (format "~a" (send e get-key-code))) render-tick)
            (demo  (handle-key-up state (format "~a" (send e get-key-release-code))) render-tick))
         
        ]
       [else w]))
   
   (define (word-tick w)
     (match-define (demo  state render-tick) w)
     (demo  (tick state) render-tick)
     )])




(define (final-state d)
  (demo-state d))



;This part is bullshit.
;  Mode lambda doesn't work on the white chromebooks we use in class
;  So I'm going to make the rendering strategy use either mode-lambda or our old home rolled system
;    depending on what kind of computer we're on...
;  Gross.  But I do have a github issue open on mode-lambda and a racket mailing list post that
;    I hope will make this crap unnecessary soon.

(define (on-white-chromebook)
   ;Check os.  Check `whoami` check number: 1.. 199

  (and (system-type 'os)
       (computer-number)
       (> 200 (computer-number))))

(define (computer-number)
  (define s (with-output-to-string
              (thunk (system "hostname"))))

  (~> s
      (string-replace _ "ts" "")
      (string-replace _ "\n" "")
      (string->number _)))


(define rendering-mode
  (if (on-white-chromebook)
      'old-method
      'new-method))

(define (get-gui)
  (if (eq? rendering-mode 'new-method)
      (make-gui #:start-fullscreen? #f #:mode gl:gui-mode)
      (make-gui #:start-fullscreen? #f)))

(define (get-render render-tick)
  (if (eq? rendering-mode 'old-method)

      ;Ignores render-tick -- which is the mode-lambda rendering function
      (and last-game-snapshot
           (g/v (draw last-game-snapshot))) ;Old, slower drawing method.  For reference...

      ;Uses render-tick -- as it should.
      (if last-game-snapshot
          (render-tick (game-entities last-game-snapshot))
          (render-tick '()))))


;End bullshit











(require 2htdp/image)


(define (fast-image->id f)
  (string->symbol (~a "id" (fast-image-id f))))

(define (add-animated-sprite-frame-new! db f)
  (define id-sym (fast-image->id f))
  
  (ml:add-sprite!/value db id-sym (fast-image-data f)))

(define (add-animated-sprite-frame! db e as f i)
  (define id-sym (fast-image->id f))
  
  (ml:add-sprite!/value db id-sym (fast-image-data f)))

(define (add-animated-sprite! db e as)
  (define frames (animated-sprite-frames as))
  (for ([f (in-vector frames)]
        [i (in-range (vector-length frames))])
    (add-animated-sprite-frame! db e as f i)))

(define (add-entity! db e)
  (add-animated-sprite! db e (get-component e animated-sprite?)))

(define (entities->compiled-sprite-database entities)
  (define sd (ml:make-sprite-db))

  (for ([e (in-list entities)])
    (and (get-component e animated-sprite?)
         (add-entity! sd e)))
  
  (define csd (ml:compile-sprite-db sd))

  ;(displayln (ml:compiled-sprite-db-spr->idx csd))
  ; (ml:save-csd! csd (build-path "/Users/thoughtstem/Desktop/sprite-db") #:debug? #t)

  csd)






(require threading)

(define temp-storage '())

(define (remember-image! f)
  (set! temp-storage
        (cons (fast-image-id f)
              temp-storage)))

(define (seen-image-before f)
  (member (fast-image-id f) temp-storage =))

(define (precompiler-entity . is)
  (define images
    (flatten
     (append
       (map fast-image (filter image? is))
       (entities->sprites-to-compile (filter entity? is)))))
  
  (register-sprites-from-images! images)

  #f)

(define should-recompile? #f)
(define compiled-images '())

(define csd       #f)  ;Mode Lambda's representation of our compiled sprites


(define (entities->sprites-to-compile entities)
  (define fast-images-from-animated-sprite
    (~> entities
        (map (curryr get-component animated-sprite?) _)
        (map (compose vector->list animated-sprite-frames) _)
        flatten))


  (define fast-images-from-precompile-component
    (flatten
     (~> entities
         (map (curryr get-components precompiler?) _)
         flatten
         (map precompiler-sprites _) 
         flatten)))

  

  (append fast-images-from-animated-sprite
          fast-images-from-precompile-component))


(define (register-sprites-from-images! images)
  (define uncompiled-images (filter-not seen-image-before images))

  (for ([image (in-list uncompiled-images)])
    (remember-image! image))

  (and (not (empty? uncompiled-images))
       (displayln "Recompile! Because:")
       (displayln (map fast-image-data uncompiled-images))
       (set! compiled-images (append compiled-images uncompiled-images))
       (set! should-recompile? #t)))


(define (register-sprites-from-entities! entities)
  ;Trigger recompile if any of the frames haven't been remembered
  (define images (entities->sprites-to-compile entities))

  (register-sprites-from-images! images))


(define (recompile!)
  (and should-recompile?
       (set! should-recompile? #f)
       (let ([sd2 (ml:make-sprite-db)])
         (for ([image (in-list compiled-images)])
           (add-animated-sprite-frame-new! sd2 image))
         
         (set! csd (ml:compile-sprite-db sd2))

         ;(displayln (ml:compiled-sprite-db-spr->idx csd))
         
         
         #t)))


(require racket/math)
(define (game->mode-lambda-sprite-list entities)
  (flatten
   (filter identity
           (for/list ([e (in-list (reverse entities))])
             (define as (get-component e animated-sprite?))
             
             (define f   (current-fast-frame as))

             (define id-sym    (fast-image->id f))

             
             (define sprite-id (ml:sprite-idx csd id-sym))

             (define (ui? e)
               (and (get-component e layer?)
                    (eq? (get-layer e) "ui")))

             (define (tops? e)  ; for treetops and rooftops
               (and (get-component e layer?)
                    (eq? (get-layer e) "tops")))

             (define layer (cond [(ui? e)   2]
                                 [(tops? e) 1]
                                 [else      0]))

             (if (or (get-component e hidden?)
                     (not sprite-id))
                 #f
                 (ml:sprite #:layer layer
                            (real->double-flonum (x e))
                            (real->double-flonum (y e))
                            sprite-id
                            #:mx (animated-sprite-x-scale as)
                            #:my (animated-sprite-y-scale as)
                            #:theta (real->double-flonum (animated-sprite-rotation as))
                            ))))))



