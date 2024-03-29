;;; -*-  Mode: Lisp; Package: Maxima; Syntax: Common-Lisp; Base: 10 -*- ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     The data in this file contains enhancments.                    ;;;;;
;;;                                                                    ;;;;;
;;;  Copyright (c) 1984,1987 by William Schelter,University of Texas   ;;;;;
;;;     All rights reserved                                            ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     (c) Copyright 1981 Massachusetts Institute of Technology         ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :maxima)

(macsyma-module laplac)

(declare-top (special dvar var-list var-parm-list var parm $savefactors
                      checkfactors $ratfac $keepfloat *nounl* *nounsflag*
                      errcatch $errormsg))

;;; The properties NOUN and VERB give correct linear display

(defprop $laplace %laplace verb)
(defprop %laplace $laplace noun)

(defprop $ilt %ilt verb)
(defprop %ilt $ilt noun)

(defprop $invlap %invlap verb)
(defprop %invlap $invlap noun)

(defun exponentiate (pow)
       ;;;COMPUTES %E**Z WHERE Z IS AN ARBITRARY EXPRESSION TAKING SOME OF THE WORK AWAY FROM SIMPEXPT
  (cond ((zerop1 pow) 1)
        ((equal pow 1) '$%e)
        (t (power '$%e pow))))

(defun fixuprest (rest)
       ;;;REST IS A PRODUCT WITHOUT THE MTIMES.FIXUPREST PUTS BACK THE MTIMES
  (cond ((null rest) 1)
        ((cdr rest) (cons '(mtimes simp) rest))
        (t (car rest))))

(defmacro posint (x)
  `(and (integerp ,x) (> ,x 0)))

(defmacro negint (x)
  `(and (integerp ,x) (< ,x 0)))

(defun isquadraticp (e x)
  (let ((b (sdiff e x)))
    (cond ((zerop1 b) (list 0 0 e))
          ((freeof x b) (list 0 b (maxima-substitute 0 x e)))
          ((setq b (islinear b x))
           (list (div* (car b) 2) (cdr b) (maxima-substitute 0 x e))))))

;;;INITIALIZES SOME GLOBAL VARIABLES THEN CALLS THE DISPATCHING FUNCTION

(defmfun $laplace (fun var parm)
  (setq fun (mratcheck fun))
  (cond ((or *nounsflag* (member '%laplace *nounl* :test #'eq))
         (setq fun (remlaplace fun))))
  (cond ((and (null (atom fun)) (eq (caar fun) 'mequal))
         (list '(mequal simp)
               (laplace (cadr fun))
               (laplace (caddr fun))))
        (t (laplace fun))))

;;;LAMBDA BINDS SOME SPECIAL VARIABLES TO NIL AND DISPATCHES

(defun remlaplace (e)
  (if (atom e)
      e
      (cons (delete 'laplace (append (car e) nil) :count 1 :test #'eq)
            (mapcar #'remlaplace (cdr e)))))

(defun laplace (fun)
  (let (dvar var-list var-parm-list)
;;; Handles easy cases and calls appropriate function on others.
    (cond ((equal fun 0) 0)
          ((equal fun 1)
           (cond ((zerop1 parm) (simplify (list '(%delta) 0)))
                 (t (power parm -1))))
          ((alike1 fun var) (power parm -2))
          ((or (atom fun) (freeof var fun))
           (cond ((zerop1 parm) (mul2 fun (simplify (list '(%delta) 0))))
                 (t (mul2 fun (power parm -1)))))
          (t
           (let ((op (caar fun)))
             (let ((result ; We store the result of laplace for further work.
               (cond ((eq op 'mplus)
                      (laplus fun))
                     ((eq op 'mtimes)
                      (laptimes (cdr fun)))
                     ((eq op 'mexpt)
                      (lapexpt fun nil))
                     ((eq op '%sin)
                      (lapsin fun nil nil))
                     ((eq op '%cos)
                      (lapsin fun nil t))
                     ((eq op '%sinh)
                      (lapsinh fun nil nil))
                     ((eq op '%cosh)
                      (lapsinh fun nil t))
                     ((eq op '%log)
                      (laplog fun))
                     ((eq op '%derivative)
                      (lapdiff fun))
                     ((eq op '%integrate)
                      (lapint fun))
                     ((eq op '%sum)
                      (list '(%sum simp)
                            (laplace (cadr fun))
                            (caddr fun)
                            (cadddr fun)
                            (car (cddddr fun))))
                     ((eq op '%erf)
                      (laperf fun))
                     ((eq op '%bessel_j)
                      (lapbesj fun))
                     ((and (eq op '%ilt)(eq (cadddr fun) var))
                      (cond ((eq parm (caddr fun))(cadr fun))
                            (t (subst parm (caddr fun)(cadr fun)))))
                     ((eq op '%delta)
                      (lapdelta fun nil))
                     ((eq op '%doublet)
                      (lapdoublet fun nil))
                     ((eq op '%heaviside)
                      (lapheavi fun nil))
                     ((setq op ($get op '$laplace))
                      (mcall op fun var parm))
                     (t (lapdefint fun)))))
              (when (isinop result '%integrate)
                ;; Laplace has not found a result but returns a definit
                ;; integral. This integral can contain internal integration
                ;; variables. Replace such a result with the noun form.
                (setq result (list '(%laplace) fun var parm)))
              ;; Check if we have a result, when not call $specint.
              (check-call-to-$specint result fun)))))))

;;; Check if laplace has found a result, when not try $specint.

(defun check-call-to-$specint (result fun)
  (cond
    ((or (isinop result '%laplace)
         (isinop result '%limit)   ; Try $specint for incomplete results
         (isinop result '%at))     ; which contain %limit or %at too.
     ;; laplace returns a noun form or a result which contains %limit or %at.
     ;; We pass the function to $specint to look for more results.
     (let (res)
       ;; laplace assumes the parameter s to be positive and does a
       ;; declaration before an integration is done. Therefore we declare
       ;; the parameter of the Laplace transform to be positive before
       ;; we call $specint too.
       (with-new-context (context)
         (progn
           (meval `(($assume) ,@(list (list '(mgreaterp) parm 0))))
           (setq res ($specint (mul fun (power '$%e (mul -1 var parm))) var))))
       (if (or (isinop res '%specint)  ; Both symobls are possible, that is
               (isinop res '$specint)) ; not consistent! Check it! 02/2009
           ;; $specint has not found a result.
           result
           ;; $specint has found a result
           res)))
       (t result)))

(defun laplus (fun)
  (simplus (cons '(mplus) (mapcar #'laplace (cdr fun))) 1 t))

(defun laptimes (fun)
       ;;;EXPECTS A LIST (PERHAPS EMPTY) OF FUNCTIONS MULTIPLIED TOGETHER WITHOUT THE MTIMES
       ;;;SEES IF IT CAN APPLY THE FIRST AS A TRANSFORMATION ON THE REST OF THE FUNCTIONS
  (cond ((null fun) (list '(mexpt simp) parm -1.))
        ((null (cdr fun)) (laplace (car fun)))
        ((freeof var (car fun))
         (simptimes (list '(mtimes)
                          (car fun)
                          (laptimes (cdr fun)))
                    1
                    t))
        ((eq (car fun) var)
         (simptimes (list '(mtimes) -1 (sdiff (laptimes (cdr fun)) parm))
                    1
                    t))
        (t
         (let ((op (caaar fun)))
           (cond ((eq op 'mexpt)
                  (lapexpt (car fun) (cdr fun)))
                 ((eq op 'mplus)
                  (laplus ($multthru (fixuprest (cdr fun)) (car fun))))
                 ((eq op '%sin)
                  (lapsin (car fun) (cdr fun) nil))
                 ((eq op '%cos)
                  (lapsin (car fun) (cdr fun) t))
                 ((eq op '%sinh)
                  (lapsinh (car fun) (cdr fun) nil))
                 ((eq op '%cosh)
                  (lapsinh (car fun) (cdr fun) t))
                 ((eq op '%delta)
                  (lapdelta (car fun) (cdr fun)))
                 ((eq op '%doublet)
                  (lapdoublet (car fun) (cdr fun)))
                 ((eq op '%heaviside)
                  (lapheavi (car fun) (cdr fun)))
                 (t
                  (lapshift (car fun) (cdr fun))))))))

(defun lapexpt (fun rest)
       ;;;HANDLES %E**(A*T+B)*REST(T), %E**(A*T**2+B*T+C),
       ;;; 1/SQRT(A*T+B), OR T**K*REST(T)
  (prog (ab base-of-fun power result)
     (setq base-of-fun (cadr fun) power (caddr fun))
     (cond
       ((and
         (freeof var base-of-fun)
         (setq
          ab
          (isquadraticp
           (cond ((eq base-of-fun '$%e) power)
                 (t (simptimes (list '(mtimes)
                                     power
                                     (list '(%log)
                                           base-of-fun))
                               1
                               nil)))
           var)))
        (cond ((equal (car ab) 0) (go %e-case-lin))
              ((null rest) (go %e-case-quad))
              (t (go noluck))))
       ((and (eq base-of-fun var) (freeof var power))
        (go var-case))
       ((and (alike1 '((rat) -1 2) power) (null rest)
             (setq ab (islinear base-of-fun var)))
        (setq result (div* (cdr ab) (car ab)))
        (return (simptimes
                 (list '(mtimes)
                       (list '(mexpt)
                             (div* '$%pi
                                   (list '(mtimes)
                                         (car ab)
                                         parm))
                             '((rat) 1 2))
                       (exponentiate (list '(mtimes) result parm))
                       (list '(mplus)
                             1
                             (list '(mtimes)
                                   -1
                                   (list '(%erf)
                                         (list '(mexpt)
                                               (list '(mtimes)
                                                     result
                                                     parm)
                                               '((rat) 1 2)))
                                   ))) 1 nil)))
       (t (go noluck)))
     %e-case-lin
     (setq result
      (cond
        (rest (sratsimp ($at (laptimes rest)
                             (list '(mequal simp)
                                   parm
                                   (list '(mplus simp)
                                         parm
                                         (afixsign (cadr ab)
                                                   nil))))))
        (t (list '(mexpt)
                 (list '(mplus)
                       parm
                       (afixsign (cadr ab) nil))
                 -1))))
     (return (simptimes (list '(mtimes)
                              (exponentiate (caddr ab))
                              result)
                        1
                        nil))
     %e-case-quad
     (setq result (afixsign (car ab) nil))
     (setq
      result
      (list
       '(mtimes)
       (div* (list '(mexpt)
                   (div* '$%pi result)
                   '((rat) 1 2))
             2)
       (exponentiate (div* (list '(mexpt) parm 2)
                           (list '(mtimes) 4 result)))
       (list '(mplus)
             1
             (list '(mtimes)
                   -1
                   (list '(%erf)
                         (div* parm
                               (list '(mtimes)
                                     2
                                     (list '(mexpt)
                                           result
                                           '((rat) 1 2)))))
                   ))))
     (and (null (equal (cadr ab) 0))
          (setq result
                (maxima-substitute (list '(mplus)
                                         parm
                                         (list '(mtimes)
                                               -1
                                               (cadr ab)))
                                   parm
                                   result)))
     (return (simptimes  (list '(mtimes)
                               (exponentiate (caddr ab))
                               result) 1 nil))
     var-case
     (cond ((or (null rest) (freeof var (fixuprest rest)))
            (go var-easy-case)))
     (cond ((posint power)
            (return (afixsign (apply '$diff
                                     (list (laptimes rest)
                                           parm
                                           power))
                              (even power))))
           ((negint power)
            (return (mydefint (hackit power rest)
                              (createname parm (- power))
                              parm)))
           (t (go noluck)))
     var-easy-case
     (setq power
           (simplus (list '(mplus) 1 power) 1 t))
     (or (eq (asksign power) '$positive) (go noluck))
     (setq result (list (list '(%gamma) power)
                        (list '(mexpt)
                              parm
                              (afixsign power nil))))
     (and rest (setq result (nconc result rest)))
     (return (simptimes (cons '(mtimes) result) 1 nil))
     noluck
     (return
       (cond
         ((and (posint power)
               (member (caar base-of-fun)
                     '(mplus %sin %cos %sinh %cosh) :test #'eq))
          (laptimes (cons base-of-fun
                          (cons (cond ((= power 2) base-of-fun)
                                      (t (list '(mexpt simp)
                                               base-of-fun
                                               (1- power))))
                                rest))))
         (t (lapshift fun rest))))))

;;;INTEGRAL FROM A TO INFINITY OF F(X)
(defun mydefint (f x a)
  (let ((tryint (and (not ($unknown f))
                     ;; $defint should not throw a Maxima error,
                     ;; therefore we set the flags errcatch and $errormsg.
                     ;; errset catches the error and returns nil
                     (with-new-context (context)
                       (progn
                         (meval `(($assume) ,@(list (list '(mgreaterp) parm 0))))
                         (meval `(($assume) ,@(list (list '(mgreaterp) x 0))))
                         (meval `(($assume) ,@(list (list '(mgreaterp) a 0))))
                         (let ((errcatch t) ($errormsg nil))
                           (errset ($defint f x a '$inf))))))))
    (if tryint
        (car tryint)
        (list '(%integrate simp) f x a '$inf))))

 ;;;CREATES UNIQUE NAMES FOR VARIABLE OF INTEGRATION
(defun createname (head tail)
  (intern (format nil "~S~S" head tail)))

;;;REDUCES LAPLACE(F(T)/T**N,T,S) CASE TO LAPLACE(F(T)/T**(N-1),T,S) CASE
(defun hackit (exponent rest)
  (cond ((equal exponent -1)
         (let ((parm (createname parm 1)))
           (laptimes rest)))
        (t (mydefint (hackit (1+ exponent) rest)
                     (createname parm (- -1 exponent))
                     (createname parm (- exponent))))))

(defun afixsign (funct signswitch)
       ;;;MULTIPLIES FUNCT BY -1 IF SIGNSWITCH IS NIL
  (cond (signswitch funct)
        (t (simptimes (list '(mtimes) -1 funct) 1 t))))

(defun lapshift (fun rest)
  (cond ((atom fun) (merror "LAPSHIFT: expected a cons, not ~M" fun))
        ((or (member 'laplace (car fun) :test #'eq) (null rest))
         (lapdefint (cond (rest (simptimes (cons '(mtimes)
                                                 (cons fun rest)) 1 t))
                          (t fun))))
        (t (laptimes (append rest
                             (ncons (cons (append (car fun)
                                                  '(laplace))
                                          (cdr fun))))))))

;;;COMPUTES %E**(W*B*%I)*F(S-W*A*%I) WHERE W=-1 IF SIGN IS T ELSE W=1
(defun mostpart (f parm sign a b)
  (let ((substinfun ($at f
                         (list '(mequal simp)
                               parm
                               (list '(mplus simp) parm (afixsign (list '(mtimes) a '$%i) sign))))))
    (if (zerop1 b)
        substinfun
        (list '(mtimes)
              (exponentiate (afixsign (list '(mtimes) b '$%i) (null sign)))
              substinfun))))

 ;;;IF WHICHSIGN IS NIL THEN SIN TRANSFORM ELSE COS TRANSFORM
(defun compose (fun parm whichsign a b)
  (let ((result (list '((rat) 1 2)
                      (list '(mplus)
                            (mostpart fun parm t a b)
                            (afixsign (mostpart fun parm nil a b)
                                      whichsign)))))
    (sratsimp (simptimes (cons '(mtimes)
                               (if whichsign
                                   result
                                   (cons '$%i result)))
                         1 nil))))

 ;;;FUN IS OF THE FORM SIN(A*T+B)*REST(T) OR COS
(defun lapsin (fun rest trigswitch)
  (let ((ab (islinear (cadr fun) var)))
    (cond (ab
           (cond (rest
                  (compose (laptimes rest)
                           parm
                           trigswitch
                           (car ab)
                           (cdr ab)))
                 (t
                  (simptimes
                   (list '(mtimes)
                    (cond ((zerop1 (cdr ab))
                           (if trigswitch parm (car ab)))
                          (t
                           (cond (trigswitch
                                  (list '(mplus)
                                        (list '(mtimes)
                                              parm
                                              (list '(%cos) (cdr ab)))
                                        (list '(mtimes)
                                              -1
                                              (car ab)
                                              (list '(%sin) (cdr ab)))))
                                 (t
                                  (list '(mplus)
                                        (list '(mtimes)
                                              parm
                                              (list '(%sin) (cdr ab)))
                                        (list '(mtimes)
                                              (car ab)
                                              (list '(%cos) (cdr ab))))))))
                    (list '(mexpt)
                          (list '(mplus)
                                (list '(mexpt) parm 2)
                                (list '(mexpt) (car ab) 2))
                          -1))
                   1 nil))))
          (t
           (lapshift fun rest)))))

 ;;;FUN IS OF THE FORM SINH(A*T+B)*REST(T) OR IS COSH
(defun lapsinh (fun rest switch)
  (cond ((islinear (cadr fun) var)
         (sratsimp
          (laplus
           (simplus
            (list '(mplus)
                  (nconc (list '(mtimes)
                               (list '(mexpt)
                                     '$%e
                                     (cadr fun))
                               '((rat) 1 2))
                         rest)
                  (afixsign (nconc (list '(mtimes)
                                         (list '(mexpt)
                                               '$%e
                                               (afixsign (cadr fun)
                                                         nil))
                                         '((rat) 1 2))
                                   rest)
                            switch))
            1
            nil))))
        (t (lapshift fun rest))))

 ;;;FUN IS OF THE FORM LOG(A*T)
(defun laplog (fun)
  (let ((ab (islinear (cadr fun) var)))
    (cond ((and ab (zerop1 (cdr ab)))
           (simptimes (list '(mtimes)
                            (list '(mplus)
                                  (subfunmake '$psi '(0) (ncons 1))
                                  (list '(%log) (car ab))
                                  (list '(mtimes) -1 (list '(%log) parm)))
                            (list '(mexpt) parm -1))
                      1 nil))
          (t
           (lapdefint fun)))))

 ;;;FUN IS OF THE FORM BESSELJ(N,A*T).
(defun lapbesj (fun)
  (let ((n (cadr fun))
        (ab (islinear (caddr fun) var)))
    (cond ((and ab (zerop1 (cdr ab)))
           (simptimes (list '(mtimes)
                            (list '(mexpt) (car ab)
                                  (list '(mtimes) -1 n))
                            (list '(mexpt)
                                  (list '(mplus)
                                        (list '(mexpt) parm 2)
                                        (list '(mexpt) (car ab) 2))
                                  (list '(rat) -1 2))
                            (list '(mexpt)
                                  (list '(mplus)
                                        (list '(mtimes) -1 parm)
                                        (list '(mexpt)
                                              (list '(mplus)
                                                    (list '(mexpt) parm 2)
                                                    (list '(mexpt) (car ab) 2))
                                              (list '(rat) 1 2)))
                                  n))
                      1 nil))
          (t (lapdefint fun)))))

(defun raiseup (fbase exponent)
  (if (equal exponent 1)
      fbase
      (list '(mexpt) fbase exponent)))

;;TAKES TRANSFORM OF DELTA(A*T+B)*F(T)
(defun lapdelta (fun rest)
  (let ((ab (islinear (cadr fun) var))
        (sign nil)
        (recipa nil))
    (cond (ab
           (setq recipa (power (car ab) -1) ab (div (cdr ab) (car ab)))
           (setq sign (asksign ab) recipa (simplifya (list '(mabs) recipa) nil))
           (simplifya (cond ((eq sign '$positive)
                             0)
                            ((eq sign '$zero)
                             (list '(mtimes)
                                   (maxima-substitute 0 var (fixuprest rest))
                                   recipa))
                            (t
                             (list '(mtimes)
                                   (maxima-substitute (neg ab) var (fixuprest rest))
                                   (list '(mexpt) '$%e (cons '(mtimes) (cons parm (ncons ab))))
                                   recipa)))
                      nil))
          (t
           (lapshift fun rest)))))

;;TAKES TRANSFORM OF DOUBLET(A*T+B)*F(T)
(defun lapdoublet (fun rest)
  (let ((ab (islinear (cadr fun) var))
        (sign nil)
        (recipa nil)
        (recipamag nil))
    (cond (ab
           (setq recipa (power (car ab) -1) ab (div (cdr ab) (car ab)))
           (setq sign (asksign ab) recipamag (simplifya (list '(mabs) recipa) nil))
           (simplifya (cond ((eq sign '$positive) 0)
                            ((eq sign '$zero)
                             (list '(mtimes)
                                   recipa recipamag
                                   (list '(mplus)
                                         (list '(mtimes)
                                               parm
                                               (maxima-substitute 0 var (fixuprest rest)))
                                         (list '(mtimes)
                                               -1
                                               ($at
                                                (sdiff (fixuprest rest) var)
                                                (list '(mequal) var 0))))))
                            (t
                             (list '(mtimes)
                                   recipa recipamag
                                   (list '(mexpt) '$%e (cons '(mtimes) (cons parm (ncons ab))))
                                   (list '(mplus)
                                         (list '(mtimes)
                                               parm
                                               (maxima-substitute (neg ab) var (fixuprest rest)))
                                         (list '(mtimes)
                                               -1
                                               ($at
                                                (sdiff (fixuprest rest) var)
                                                (list '(mequal) var (neg ab))))))))
                      nil))
          (t
           (lapshift fun rest)))))

;;TAKES TRANSFORM OF HEAVISIDE(A*T+B)*F(T)
(defun lapheavi (fun rest)
  (let ((ab (islinear (cadr fun) var))
        (signa nil)
        (signb nil))
    (cond (ab
           (setq signa (asksign (car ab)))
           (setq signb (asksign (cdr ab)))
           (setq ab (div (cdr ab) (car ab)))
           (cond ((eq signa signb) (laptimes rest))
                 ((eq signa '$positive)
                  (cond ((eq ab 0) (laptimes rest))
                        (t
                         (list '(mtimes)
                               (list '(mexpt) '$%e
                                     (list '(mtimes) parm ab))
                               (laptimes (mapcar #'(lambda (x) (maxima-substitute (list '(mplus) var (neg ab)) var x)) rest))))))
                 (t
                  (cond ((eq ab 0) 0)
                        (t
                         (list '(mplus)
                               (list '(mtimes) -1
                                     (laptimes (append (list (list '(%heaviside)
                                                                   (list '(mplus)
                                                                         var
                                                                         ab)))
                                                       rest)))
                               (laptimes rest)))))))
          (t
           (lapshift fun rest)))))


(defun laperf (fun)
  (let ((ab (islinear (cadr fun) var)))
    (cond ((and ab (equal (cdr ab) 0))
           (simptimes (list '(mtimes)
                            (div* (exponentiate (div* (list '(mexpt) parm 2)
                                                      (list '(mtimes)
                                                            4
                                                            (list '(mexpt) (car ab) 2))))
                                  parm)
                            (list '(mplus)
                                  1
                                  (list '(mtimes)
                                        -1
                                        (list '(%erf) (div* parm (list '(mtimes) 2 (car ab)))))))
                      1
                      nil))
          (t
           (lapdefint fun)))))

(defun lapdefint (fun)
  (prog (tryint mult)
     (and ($unknown fun)(go skip))
     (setq mult (simptimes (list '(mtimes) (exponentiate
                                            (list '(mtimes simp) -1 var parm)) fun) 1 nil))
     (with-new-context (context)
       (progn
         (meval `(($assume) ,@(list (list '(mgreaterp) parm 0))))
         (setq tryint
               ;; $defint should not throw a Maxima error.
               ;; therefore we set the flags errcatch and errormsg.
               ;; errset catches an error and returns nil.
               (let ((errcatch t) ($errormsg nil))
                 (errset ($defint mult var 0 '$inf))))))
     (and tryint (not (eq (and (listp (car tryint))
                               (caaar tryint))
                          '%integrate))
          (return (car tryint)))
     skip (return (list '(%laplace simp) fun var parm))))


(defun lapdiff (fun)
;;;FUN IS OF THE FORM DIFF(F(T),T,N) WHERE N IS A POSITIVE INTEGER
  (prog (difflist degree frontend resultlist newdlist order arg2)
     (setq newdlist (setq difflist (copy-tree (cddr fun))))
     (setq arg2 (list '(mequal simp) var 0))
     a    (cond ((null difflist)
                 (return (cons '(%derivative simp)
                               (cons (list '(%laplace simp)
                                           (cadr fun)
                                           var
                                           parm)
                                     newdlist))))
                ((eq (car difflist) var)
                 (setq degree (cadr difflist)
                       difflist (cddr difflist))
                 (go out)))
     (setq difflist (cdr (setq frontend (cdr difflist))))
     (go a)
     out  (cond ((null (posint degree))
                 (return (list '(%laplace simp) fun var parm))))
     (cond (frontend (rplacd frontend difflist))
           (t (setq newdlist difflist)))
     (cond (newdlist (setq fun (cons '(%derivative simp)
                                     (cons (cadr fun)
                                           newdlist))))
           (t (setq fun (cadr fun))))
     (setq order 0)
     loop (decf degree)
     (setq resultlist
           (cons (list '(mtimes)
                       (raiseup parm degree)
                       ($at ($diff fun var order) arg2))
                 resultlist))
     (incf order)
     (and (> degree 0) (go loop))
     (setq resultlist (cond ((cdr resultlist)
                             (cons '(mplus)
                                   resultlist))
                            (t (car resultlist))))
     (return (simplus (list '(mplus)
                            (list '(mtimes)
                                  (raiseup parm order)
                                  (laplace fun))
                            (list '(mtimes)
                                  -1
                                  resultlist))
                      1 nil))))

 ;;;FUN IS OF THE FORM INTEGRATE(F(X)*G(T)*H(T-X),X,0,T)
(defun lapint (fun)
  (prog (newfun parm-list f)
     (and dvar (go convolution))
     (setq dvar (cadr (setq newfun (cdr fun))))
     (and (cddr newfun)
          (zerop1 (caddr newfun))
          (eq (cadddr newfun) var)
          (go convolutiontest))
     notcon
     (setq newfun (cdr fun))
     (cond ((cddr newfun)
            (cond ((and (freeof var (caddr newfun))
                        (freeof var (cadddr newfun)))
                   (return (list '(%integrate simp)
                                 (laplace (car newfun))
                                 dvar
                                 (caddr newfun)
                                 (cadddr newfun))))
                  (t (go giveup))))
           (t (return (list '(%integrate simp)
                            (laplace (car newfun))
                            dvar))))
     giveup
     (return (list '(%laplace simp) fun var parm))
     convolutiontest
     (setq newfun ($factor (car newfun)))
     (cond ((eq (caar newfun) 'mtimes)
            (setq f (cadr newfun) newfun (cddr newfun)))
           (t (setq f newfun newfun nil)))
     gothrulist
     (cond ((freeof dvar f)
            (setq parm-list (cons f parm-list)))
           ((freeof var f) (setq var-list (cons f var-list)))
           ((freeof dvar
                    (sratsimp (maxima-substitute (list '(mplus)
                                                       var
                                                       dvar)
                                                 var
                                                 f)))
            (setq var-parm-list (cons f var-parm-list)))
           (t (go notcon)))
     (cond (newfun (setq f (car newfun) newfun (cdr newfun))
                   (go gothrulist)))
     (and
      parm-list
      (return
        (laplace
         (cons
          '(mtimes)
          (nconc parm-list
                 (ncons (list '(%integrate)
                              (cons '(mtimes)
                                    (append var-list
                                            var-parm-list))
                              dvar
                              0
                              var)))))))
     convolution
     (return
       (simptimes
        (list
         '(mtimes)
         (laplace ($expand (maxima-substitute var
                                              dvar
                                              (fixuprest var-list))))
         (laplace
          ($expand (maxima-substitute 0 dvar (fixuprest var-parm-list)))))
        1
        t))))

(declare-top (special varlist ratform ils ilt))

;;; Note: I've added the functions $invlap, invlap, reminvlap, invlaplus,
;;; invlaptimes, invlapmult, invlapexpt, invlapdiff.

;;; invlap will use the already existing ilt structure to handle rational
;;; expressions.  The functions reminvlap and $invlap are both nearly
;;; verbatim counterparts of the corresponding laplace functions, though
;;; I do not necessarily understand how those work.

(defmfun $invlap (exp ils ilt)
  (cond ((or *nounsflag* (member '%invlap *noun1* :test #'eq))
         (setq exp (reminvlap exp))))
  (cond ((and (null (atom fun)) (eq (caar fun) 'mequal))
         (list '(mequal simp)
               (invlap (cadr exp))
               (invlap (caddr exp))))
        (t (invlap exp))))

(defun reminvlap (e)
  (if (atom e)
      e
      (cons (delete 'invlap (append (car e) nil) :count 1 :test #'eq)
            (mapcar #'reminvlap (cdr e)))))

(defun invlap (exp)
  (let ()
;;; Handles easy cases and calls appropriate function on others.
    (cond ((equal exp 0) 0)
          ((equal exp 1) (simplify (list '(%delta) ilt)))
          ((alike1 exp ils) (simplify (list '(%doublet) ilt)))
          ((or (atom exp) (freeof ils exp))
           (mul2 exp (simplify (list '(%delta) ilt))))
          (t
           (let ((op (caar exp)))
             (let ((result ;Store result of inverse laplace for further work
                    (cond ((eq op 'mplus)
                           (invlaplus exp))
                          ((eq op 'mtimes)
                           (invlaptimes (cdr exp)))
                          ((eq op 'mexpt)
                           (invlapexpt exp))
                          ((eq op '%derivative)
                           (invlapdiff exp))
                          ((eq op '%sum)
                           (list '(%sum simp)
                                 (invlap (cadr exp))
                                 (caddr exp)
                                 (cadddr exp)
                                 (car (cddddr exp))))
)))))))))

(defun invlaplus (exp)
  (simplus (cons '(mplus) (mapcar #'invlap (cdr exp))) 1 t))

(defun invlapdiff (exp)
;;;EXP IS OF THE FORM DIFF(F(S),S,N), WITH N A POSITIVE INTEGER
  (let (difflist vardegree newdlist sdegree)
    (setq difflist (cddr exp))
    (loop (cond ((null difflist)
                 (return (list '(mtimes)
                               (list '(mexpt) ilt sdegree)
                               (list '(%derivative)
                                     (list '(%invlap) (cadr exp) ils ilt)
                                     newdlist))))
                (t
                 (setq vardegree ((car difflist) (cadr difflist)))
                 (setq difflist (cddr difflist))
                 (cond ((eq (car vardegree) ils)
                        (setq sdegree (cadr vardegree)))
                       (t
                        (setq newdlist (append newdlist vardegree)))))))
))

;;Fill in invlaptimes, invlapexpt, invlapdiff, invlaplog

(defmfun $ilt (exp ils ilt)
 ;;;EXP IS F(S)/G(S) WHERE F AND G ARE POLYNOMIALS IN S AND DEGR(F) < DEGR(G)
  (let (varlist ($savefactors t) checkfactors $ratfac $keepfloat)
                ;;; MAKES ILS THE MAIN VARIABLE
    (setq varlist (list ils))
    (newvar exp)
    (orderpointer varlist)
    (setq var (caadr (ratrep* ils)))
    (cond ((and (null (atom exp))
                (eq (caar exp) 'mequal))
           (list '(mequal)
                 ($ilt (cadr exp) ils ilt)
                 ($ilt (caddr exp) ils ilt)))
          ((zerop1 exp) 0)
          ((freeof ils exp)
           (list '(%ilt simp) exp ils ilt))
          (t (ilt0 exp)))))

(defun maxima-rationalp (le v)
  (cond ((null le))
        ((and (null (atom (car le))) (null (freeof v (car le))))
         nil)
        (t (maxima-rationalp (cdr le) v))))

 ;;;THIS FUNCTION DOES THE PARTIAL FRACTION DECOMPOSITION
(defun ilt0 (exp)
  (prog (wholepart frpart num denom y content real factor
         apart bpart parnumer ratarg ratform)
     (and (mplusp exp)
          (return (simplus  (cons '(mplus)
                                  (mapcar #'(lambda (f) ($ilt f ils ilt)) (cdr exp))) 1 t)))
     (and (null (atom exp))
          (eq (caar exp) '%laplace)
          (eq (cadddr exp) ils)
          (return (cond ((eq (caddr exp) ilt) (cadr exp))
                        (t (subst ilt
                                  (caddr exp)
                                  (cadr exp))))))
     (setq ratarg (ratrep* exp))
     (or (maxima-rationalp varlist ils)
         (return (list '(%ilt simp) exp ils ilt)))
     (setq ratform (car ratarg))
     (setq denom (ratdenominator (cdr ratarg)))
     (setq frpart (pdivide (ratnumerator (cdr ratarg)) denom))
     (setq wholepart (car frpart))
     (setq frpart (ratqu (cadr frpart) denom))
     (cond ((not (zerop1 (car wholepart)))
            (return (list '(%ilt simp) exp ils ilt)))
           ((zerop1 (car frpart)) (return 0)))
     (setq num (car frpart) denom (cdr frpart))
     (setq y (oldcontent denom))
     (setq content (car y))
     (setq real (cadr y))
     (setq factor (pfactor real))
     loop (cond ((null (cddr factor))
                 (setq apart real
                       bpart 1
                       y '((0 . 1) 1 . 1))
                 (go skip)))
     (setq apart (pexpt (car factor) (cadr factor)))
     (setq bpart (car (ratqu real apart)))
     (setq y (bprog apart bpart))
     skip (setq frpart
                (cdr (ratdivide (ratti (ratnumerator num)
                                       (cdr y)
                                       t)
                                (ratti (ratdenominator num)
                                       (ratti content apart t)
                                       t))))
     (setq
      parnumer
      (cons (ilt1 (ratqu (ratnumerator frpart)
                         (ratti (ratdenominator frpart)
                                (ratti (ratdenominator num)
                                       content
                                       t)
                                t))
                  (car factor)
                  (cadr factor))
            parnumer))
     (setq factor (cddr factor))
     (cond ((null factor)
            (return (simplus (cons '(mplus) parnumer) 1 t))))
     (setq num (cdr (ratdivide (ratti num (car y) t)
                               (ratti content bpart t))))
     (setq real bpart)
     (go loop)))

(declare-top (special q z))

(defun ilt1 (p q k)
  (let (z)
    (cond ((onep1 k) (ilt3 p ))
          (t (setq z (bprog q (pderivative q var)))
             (ilt2 p k)))))


 ;;;INVERTS P(S)/Q(S)**K WHERE Q(S)  IS IRREDUCIBLE
 ;;;DOESN'T CALL ILT3 IF Q(S) IS LINEAR
(defun ilt2 (p k)
  (prog (y a b)
     (and (onep1 k) (return (ilt3 p)))
     (decf k)
     (setq a (ratti p (car z) t))
     (setq b (ratti p (cdr z) t))
     (setq y (pexpt q k))
     (cond
       ((or (null (equal (pdegree q var) 1))
            (> (pdegree (car p) var) 0))
        (return
          (simplus
           (list
            '(mplus)
            (ilt2
             (cdr (ratdivide (ratplus a (ratqu (ratderivative b var) k)) y))
             k)
            ($multthru (simptimes (list '(mtimes)
                                        ilt
                                        (power k -1)
                                        (ilt2 (cdr (ratdivide b y)) k))
                                  1
                                  t)))
           1
           t))))
     (setq a (disrep (polcoef q 1))
           b (disrep (polcoef q 0)))
     (return
       (simptimes (list '(mtimes)
                        (disrep p)
                        (raiseup ilt k)
                        (simpexpt (list '(mexpt)
                                        '$%e
                                        (list '(mtimes)
                                              -1
                                              ilt
                                              b
                                              (list '(mexpt) a -1)))
                                  1
                                  nil)
                        (list '(mexpt)
                              a
                              (- -1 k))
                        (list '(mexpt)
                              (factorial k)
                              -1))
                  1
                  nil))))

(declare-top(notype k))

;;(DEFUN COEF MACRO (POL) (SUBST (CADR POL) (QUOTE DEG)
;;  '(DISREP (RATQU (POLCOEF (CAR P) DEG) (CDR P)))))

(defmacro coef (pol)
  `(disrep (ratqu (polcoef (car p) ,pol) (cdr p))))

(defmfun lapsum (&rest args)
  (cons '(mplus) args))

(defmfun lapprod (&rest args)
  (cons '(mtimes) args))

(defmfun expo (&rest args)
  (cons '(mexpt) args))

;;;INVERTS P(S)/Q(S) WHERE Q(S) IS IRREDUCIBLE
(defun ilt3 (p)
  (prog (discrim sign a c d e b1 b0 r term1 term2 degr)
     (setq e (disrep (polcoef q 0))
           d (disrep (polcoef q 1))
           degr (pdegree q var))
     (and (equal degr 1)
          (return
            (simptimes (lapprod
                        (disrep p)
                        (expo d -1)
                        (expo '$%e (lapprod -1 ilt e (expo d -1))))
                       1
                       nil)))
     (setq c (disrep (polcoef q 2)))
     (and (equal degr 2) (go quadratic))
     (and (equal degr 3) (zerop1 c) (zerop1 d)
          (go cubic))
     (return (list '(%ilt simp) (div* (disrep p)(disrep q)) ils ilt))
     cubic (setq  a (disrep (polcoef q 3))
                  r (simpnrt (div* e a) 3))
     (setq d (div* (disrep p)(lapprod a (lapsum
                                         (expo ils 3)(expo '%r 3)))))
     (return (ilt0 (maxima-substitute r '%r ($partfrac d ils))))
     quadratic (setq b0 (coef 0) b1 (coef 1))

     (setq discrim
           (simplus (lapsum
                     (lapprod 4 e c)
                     (lapprod -1 d d))
                    1
                    nil))
     (setq sign (cond ((free discrim '$%i) (asksign discrim)) (t '$positive))
           term1 '(%cos)
           term2 '(%sin))
     (setq degr (expo '$%e (lapprod ilt d (power c -1) '((rat simp) -1 2))))
     (cond ((eq sign '$zero)
            (return (simptimes (lapprod degr (lapsum (div* b1 c)
                                                     (lapprod
                                                      (div* (lapsum (lapprod 2 b0 c) (lapprod -1 b1 d))
                                                            (lapprod 2 c c)) ilt))) 1 nil))
            )              ((eq sign '$negative)
            (setq term1 '(%cosh)
                  term2 '(%sinh)
                  discrim (simptimes (lapprod -1 discrim) 1 t))))
     (setq discrim (simpnrt discrim 2))
     (setq sign
      (simptimes
       (lapprod
        (lapsum
         (lapprod 2 b0 c)
         (lapprod -1 b1 d))
        (expo discrim -1))
       1
       nil))
     (setq c (power c -1))
     (setq discrim (simptimes (lapprod
                               discrim
                               ilt
                               '((rat simp) 1 2)
                               c)
                              1
                              t))
     (return
       (simptimes
        (lapprod c degr
         (lapsum
          (lapprod b1 (list term1 discrim))
          (lapprod sign (list term2 discrim))))
        1
        nil))))

(declare-top (unspecial dvar ils ilt *nounl* parm q ratform var
                        varlist var-list var-parm-list z))
