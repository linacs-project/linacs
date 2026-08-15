;;;; src/json.lisp
;;;;
;;;; Minimal JSON encoding for the CLI reporter additions (REFACTOR.org
;;;; Action 10, thought 19). No external dependency: a purpose-built encoder
;;;; for the data shapes LINACS actually emits -- plists (action plans,
;;;; provider data), nested lists, keywords, strings, numbers, booleans,
;;;; and nil.
;;;;
;;;; This is intentionally a writer only. It round-trips through a
;;;; test-only parser in tests/cli/report.lisp so the 'JSON parses'
;;;; acceptance criterion is pinned by the suite.

(in-package :linacs.core)

(defun json-escape-string (string)
  "Return STRING with the JSON-required escapes applied (\\\", \\\\\\\\, \\n,
\\r, \\t, and control chars as \\uXXXX). Non-ASCII characters pass through
raw, which is valid UTF-8 JSON."
  (with-output-to-string (out)
    (loop for char across string
          do (case char
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (otherwise
                (if (and (char< char #\Space) (not (char= char #\Tab)))
                    (format out "\\u~4,'0x" (char-code char))
                    (write-char char out)))))))

(defun json-quote-string (string)
  "Encode STRING as a JSON string literal, including quotes."
  (format nil "\"~a\"" (json-escape-string string)))

(defun json-key-name (key)
  "Turn a keyword KEY into its JSON property name: the string value of its
symbol, lowercased (:EMACS -> \"emacs\")."
  (string-downcase (string key)))

(defun json-join (separator items)
  "Join ITEMS (strings) with SEPARATOR into a single string."
  (with-output-to-string (out)
    (loop for (item . more) on items
          do (write-string item out)
             (when more (write-string separator out)))))

(defun encode-json (value)
  "Encode VALUE as a JSON string.

Handles: NIL -> null, T -> true, strings, numbers, keywords (as
lowercased strings), symbols (as lowercased strings), plists (lists whose
first element is a keyword, encoded as objects), dotted pairs (encoded as
objects), and proper lists (encoded as arrays).

Examples:
    (encode-json '(:action :package :target :emacs :via :system))
      => \"{\\\"action\\\":\\\"package\\\",\\\"target\\\":\\\"emacs\\\",\\\"via\\\":\\\"system\\\"}\"
    (encode-json '(\"a\" \"b\"))
      => \"[\\\"a\\\",\\\"b\\\"]\"
    (encode-json '(:ensure (\"line1\" \"line2\")))
      => \"{\\\"ensure\\\":[\\\"line1\\\",\\\"line2\\\"]}\"

Plist keys must be keywords (LINACS action plists always are). Unknown
objects fall back to their PRINC-TO-STRING form as a JSON string."
  (cond
    ((null value) "null")
    ((eq value t) "true")
    ((stringp value) (json-quote-string value))
    ((numberp value) (princ-to-string value))
    ((keywordp value) (json-quote-string (json-key-name value)))
    ((symbolp value) (json-quote-string (string-downcase (string value))))
    ((consp value)
     (cond
       ((not (listp (cdr value)))
        ;; dotted pair -> object
        (format nil "{~a:~a}"
                (if (keywordp (car value))
                    (json-quote-string (json-key-name (car value)))
                    (encode-json (car value)))
                (encode-json (cdr value))))
       ((keywordp (car value))
        ;; proper plist -> object
        (let ((pairs '()))
          (loop for (key val) on value by #'cddr
                do (push (format nil "~a:~a"
                                 (json-quote-string (json-key-name key))
                                 (encode-json val))
                         pairs))
          (format nil "{~a}" (json-join "," (nreverse pairs)))))
       (t
        ;; proper list -> array
        (format nil "[~a]" (json-join "," (mapcar #'encode-json value))))))
    (t (json-quote-string (princ-to-string value)))))
