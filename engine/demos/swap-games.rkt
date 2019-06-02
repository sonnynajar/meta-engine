#lang racket

(require "../main.rkt"
         2htdp/image)

(define bouncing-ball
  (entity
    (position (posn 200 200))
    (sprite (register-sprite (circle 20 'solid 'blue)))))

(define spinning-square
  (entity
    (position (posn 200 200))
    (sprite (register-sprite (square 20 'solid 'red)))))

(define bb
  (game bouncing-ball)) 

(define ss
  (game spinning-square)) 

(define numbers 
  (stream-map
    (lambda (i)
      (floor (/ i 100)))
    (in-naturals)))

(define controller
  (entity
    (name 'controller)
    (number-stream numbers
                   (stream-rest (get-number-stream)))

    (counter 0 
             (stream-first (get-number-stream)))

    (toggle #f (odd? (get-counter)))))

(define main
  (game
    controller
    (entity  
      (name 'bouncing-ball)
      (sub-game bb 
                (if (get 'controller 'toggle)
                  (tick! (get-sub-game))
                  (get-sub-game)))
      (also-render
        bb 
        (if (get 'controller 'toggle)
          (game)
          (get-sub-game))))

    (entity  
      (name 'spinning-square)
      (sub-game ss 
                (if (not (get 'controller 'toggle))
                  (tick! (get-sub-game))
                  (get-sub-game)))
      (also-render
        ss 
        (if (not (get 'controller 'toggle))
          (game)
          (get-sub-game))))))


(play! main)




