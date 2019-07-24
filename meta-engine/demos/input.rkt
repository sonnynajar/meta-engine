#lang racket

(require meta-engine
         2htdp/image)


(define e
  (entity 
    (position (posn 200 200) 
              (posn-add 
                (get-position)
		(as-posn (get-current-input))))

    (sprite (register-sprite (circle 5 'solid 'green)))))


(define g
  (game (input-manager) e))

(play! g)  
