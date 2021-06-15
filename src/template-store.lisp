(in-package #:djula)

(defgeneric find-template (store name &optional error-p)
  (:documentation "Return a hashable key that uniquely identifies the named template."))

(defgeneric fetch-template (store key)
  (:documentation "Return the text of the template identified by the given key."))

;; TODO: Is there a way to make CURRENT-PATH dynamic?
(defclass file-store ()
  ((current-path
    :initform nil
    :type (or null string pathname)
    :documentation "The location of the most-recently fetched template.")
   (search-path
    :initarg :search-path
    :accessor search-path
    :initform nil
    :type list
    :documentation "User-provided list of template locations."))
  (:documentation "Searches for template files on disk according to the given search path."))

(defmethod find-template ((store file-store) name &optional (error-p t))
  "Algorithm that finds a template in a file-store."
  (with-slots (current-path search-path)
      store
    (or
     (cond
       ;; If it is a pathname, just check that the file exists
       ((pathnamep name)
        (uiop:file-exists-p name))
       ;; If first character is a '/', then treat it as an absolute path first, then relative to template store search paths.
       ((char= (char name 0) #\/)
        (or
         (uiop:file-exists-p name)
         (loop
           for dir in search-path
             thereis (uiop:file-exists-p (merge-pathnames (subseq (string name) 1) dir)))))
       ;; Otherwise, search relative to either current path or search paths
       (t (loop
             with path = (if current-path
                             (cons (directory-namestring current-path) search-path)
                             search-path)
             for dir in path
             thereis (uiop:file-exists-p (merge-pathnames name dir)))))
     (when error-p
       (error "Template ~A not found" name)))))

(defmethod fetch-template ((store file-store) name)
  (with-slots (current-path)
      store
    (setf current-path name)
    (and name (slurp (find-template store name)))))

(defvar *current-store* (make-instance 'file-store)
  "The currently in-use template store.  Defaults to a FILE-STORE.")

(defun add-template-directory (directory &optional (template-store *current-store*))
  "Adds DIRECTORY to the search path of the TEMPLATE-STORE."
  (pushnew directory
           (search-path template-store)
           :test #'equalp))

(defun find-template* (name &optional (error-p t))
  "Find template with name NAME in *CURRENT-STORE*.
If the template is not found, an error is signaled depending on ERROR-P argument value."
  (find-template *current-store* name error-p))

(defun fetch-template* (key)
  "Return the text of a template fetched from the *CURRENT-STORE*."
  (fetch-template *current-store* key))

(defun slurp (pathname)
  (with-open-file (stream pathname :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence octets stream)
      (babel:octets-to-string octets))))
