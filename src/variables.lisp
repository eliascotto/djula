(in-package #:djula)

(defvar *auto-escape* t)

;;; truncatechars:"30" => (:truncatechars 30)
(defun parse-filter-string (string)
  (if-let ((colon (position #\: string)))
    (list (make-keyword (string-upcase (subseq string 0 colon)))
          (string-trim '(#\") (subseq string (1+ colon))))
    (list (make-keyword (string-upcase string)))))

(defun integer-or-keyword (string)
  "If the STRING is an integer return an integer, otherwise return STRING as a
keyword."
  (if (every 'digit-char-p string)
      (parse-integer string)
      (make-keyword (string-upcase string))))

;;; foo.bar.baz.2 => (:foo :bar :baz 2)
(defun parse-variable-phrase (string)
  (if-let ((dot (position #\. string)))
    (cons (integer-or-keyword (subseq string 0 dot))
          (parse-variable-phrase (subseq string (1+ dot))))
    (list (integer-or-keyword string))))

;;; foo.bar.baz.2 | truncatechars:"30" | upper => ((:foo :bar :baz 2) (:truncatechars 30) (:upper))
(defun parse-variable-clause (unparsed-string)
  (destructuring-bind (var . filter-strings)
      (mapcar (lambda (s)
                (string-trim '(#\space #\tab #\newline #\return) s))
              (split-sequence:split-sequence #\| unparsed-string))
    (cons (parse-variable-phrase var)
          (mapcar #'parse-filter-string filter-strings))))

(def-token-processor :unparsed-variable (unparsed-string) rest
  ":PARSED-VARIABLE tokens are parsed into :VARIABLE tokens by PROCESS-TOKENS"
  (cons (list* :variable (parse-variable-clause unparsed-string))
        (process-tokens rest)))

(defun apply-keys/indexes (thing keys/indexes)
  (reduce (lambda (thing key)
            (handler-case
                (cond
                  ((numberp key) (elt thing key))
                  ((keywordp key)
                   (multiple-value-bind (val accessed-p)
                       (access:access thing key)
                     (if accessed-p
                         val
                         (access:access thing (intern (symbol-name key)
                                                      *djula-execute-package*)))))
                  (t (access:access thing key)))
              (error (e)
                (template-error-string* e
                                        "There was an error while accessing the ~A ~S of the object ~S"
                                        (if (numberp key)
                                            "index"
                                            "attribute")
                                        key
                                        thing))))
          keys/indexes
          :initial-value thing))

(defun get-variable (name)
  "takes a variable `NAME' and returns:
   1. the value of `NAME'
   2. any error string generated by the lookup (if there is an error string then the
      lookup was unsuccessful)"
  (access:access *template-arguments* name))

(defun resolve-variable-phrase (list)
  "takes a list starting wise a variable and ending with 0 or more keys or indexes [this
is a direct translation from the dot (.) syntax] and returns two values:

   1. the result [looking up the var and applying index/keys]
   2. an error string if something went wrond [note: if there is an error string then
the result probably shouldn't be considered useful."
  (aand (get-variable (first list))
        (apply-keys/indexes it (rest list))))

(def-token-compiler :variable (variable-phrase &rest filters)
  ;; check to see if the "dont-escape" filter is used
  ;; "safe" takes precedence before "escape"
  (let ((dont-escape
         (or
          (find '(:safe) filters :test #'equal) ; safe filter used
          (and (not *auto-escape*)              ; autoescape off and no escape filter used
               (not (find '(:escape) filters :test #'equal))))))
    ;; return a function that resolves the variable-phase and applies the filters
    (lambda (stream)
      (multiple-value-bind (ret error-string)
          (resolve-variable-phrase variable-phrase)
        (if error-string
            (with-template-error error-string
              (error error-string))
            (let ((filtered-ret
                   (princ-to-string
                    (or
                     (apply-filters
                      ret filters)
                     ""))))
              (princ (if dont-escape
                         filtered-ret
                         (escape-for-html filtered-ret))
                     stream)))))))
