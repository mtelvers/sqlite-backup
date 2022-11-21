(lang dune 3.5)

(name sqlite3-backup)

(generate_opam_files true)

(source
 (github mtelvers/sqlite3-backup))

(authors "Mark Elvers")

(maintainers "Mark Elvers")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name sqlite3-backup)
 (synopsis "Backup a SQLite3 database")
 (description "Backup a SQLite3 database")
 (depends
  ocaml
  dune
  sqlite3
  fmt
  (cmdliner (>= 1.1.0)))
 (tags
  (topics "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
