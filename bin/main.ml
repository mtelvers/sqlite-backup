
let t_src = "sqlite.db"
let t_dst = "backup-sqlite.db"

let or_fail label x =
  match x with
  | Sqlite3.Rc.OK -> ()
  | err -> Fmt.failwith "Sqlite3 %s error: %s" label (Sqlite3.Rc.to_string err)

let src = Sqlite3.db_open t_src

let () = List.iter ( fun sql -> Sqlite3.exec src sql |> or_fail sql )
[ "PRAGMA busy_timeout=10000"; "PRAGMA temp_store=MEMORY"; ]

let journal_mode = 
  let query_stmt = Sqlite3.prepare src "PRAGMA journal_mode" in
    let () = Sqlite3.reset query_stmt |> or_fail "reset query" in
    match Sqlite3.step query_stmt with
      | Sqlite3.Rc.ROW -> Sqlite3.Data.to_string_exn (Sqlite3.column query_stmt 0)
      | err -> Fmt.failwith "Sqlite3 page_size error: %s" (Sqlite3.Rc.to_string err)

let page_size = 
  let query_stmt = Sqlite3.prepare src "PRAGMA page_size" in
    let () = Sqlite3.reset query_stmt |> or_fail "reset query" in
    match Sqlite3.step query_stmt with
      | Sqlite3.Rc.ROW -> Sqlite3.Data.to_int_exn (Sqlite3.column query_stmt 0)
      | err -> Fmt.failwith "Sqlite3 page_size error: %s" (Sqlite3.Rc.to_string err)

let () = let st = Unix.stat t_src in
  Fmt.pr "Source database is %i KB" (st.st_size / 1024)

let _ = 
  match journal_mode with
    | "wal" ->
      let st = Unix.stat (t_src ^ "-wal") in
        let wal_pages = (min st.st_size (1024 * 1024 * 1024)) / page_size in
          if wal_pages > 2000 then begin
            let sql = "PRAGMA cache_size=" ^ (string_of_int wal_pages) in
              Sqlite3.exec src sql |> or_fail sql
          end ;
       Fmt.pr " plus %i KB WAL\n" (st.st_size / 1024)
    | _ -> Fmt.pr "\n"

let dst = Sqlite3.db_open t_dst

let () = List.iter ( fun sql -> Sqlite3.exec dst sql |> or_fail sql )
[ "PRAGMA synchronous=OFF"; "PRAGMA journal_mode=TRUNCATE"; "PRAGMA temp_store=MEMORY"; "PRAGMA cache_size=1"; ]

let backup = (Sqlite3.Backup.init ~dst ~dst_name:"main" ~src ~src_name:"main")

let () = (Sqlite3.Backup.step backup 0 |> or_fail "backup step")

let () = Fmt.pr "Backing up %i pages from %s\n" (Sqlite3.Backup.remaining backup) t_src

let start = Unix.gettimeofday ()

let () = 
  let rec run () = match (Sqlite3.Backup.step backup (-1)) with
    | Sqlite3.Rc.LOCKED -> Unix.sleep 10; run ()
    | Sqlite3.Rc.BUSY -> run ()
    | Sqlite3.Rc.DONE -> ()
    | err -> Fmt.pr "Sqlite3 error: %s" (Sqlite3.Rc.to_string err)
    in run ()

let stop= Unix.gettimeofday ()

let () = Fmt.pr "Backup up %i pages to %s in %f seconds\n" (Sqlite3.Backup.pagecount backup) t_dst (stop -. start)

let () = (Sqlite3.Backup.finish backup |> or_fail "backup finished")

let () = Sqlite3.exec dst ("PRAGMA journal_mode=" ^ journal_mode) |> or_fail "failed to set journal_mode"

let () = if not (Sqlite3.db_close src && Sqlite3.db_close dst) then
  Fmt.failwith "Sqlite3 close error"


