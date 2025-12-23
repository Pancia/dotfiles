#!/usr/bin/env hy

(import os)
(import re)
(import sys)

(defn process-file
  [file-path pattern-type pattern replacement]
  (try
    (with [f (open file-path "r")] (setv content (.read f)))
    (setv content
      (cond
        (= pattern-type "literal")
          (do
            (print pattern replacement)
            (.replace content pattern
              (.replace (.replace replacement "\\n" "\n") "\\t" "\t")))
        (= pattern-type "regex") (re.sub pattern replacement content)
        True content))
    (with [f (open file-path "w")] (.write f content))
    (print f "Processed: {file-path}")
    (except [e Exception] (print f "Error processing {file-path}: {e}"))))

(defn process-folder
  [folder-path pattern-type pattern replacement]
  (try
    (for [#(root dirs files) (os.walk folder-path)]
      (for [file-name files]
        (process-file (os.path.join root file-name) pattern-type pattern
          replacement)))
    (except [e Exception]
      (print f "Error processing folder {folder-path}: {e}"))))

(defn main
  []
  (input
    "PATH PATTERN_TYPE PATTERN REPLACEMENT: did you remember to escape the pattern? (* or <ctrl-c>)")
  (setv path (get sys.argv 1))
  (setv pattern-type (get sys.argv 2))
  (when (not (in pattern-type ["regex" "literal"]))
    (print "unrecognized pattern type")
    (return 1))
  (setv pattern
    (if (= pattern-type "regex")
      (re.compile (get sys.argv 3))
      (get sys.argv 3)))
  (setv replacement (get sys.argv 4))
  (if (os.path.isfile path)
    (process-file path pattern-type pattern replacement)
    (process-folder path pattern-type pattern replacement)))

(when (= __name__ "__main__") (main))
