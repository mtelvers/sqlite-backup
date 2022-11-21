open Sqlite3
open Cmdliner

let or_fail label x =
  match x with
  | Rc.OK -> ()
  | err -> Fmt.failwith "Sqlite3 %s error: %s" label (Rc.to_string err)

let sqlite_backup t_src t_dst =

  let src = db_open t_src in

  let () = List.iter ( fun sql -> exec src sql |> or_fail sql )
  [ "PRAGMA busy_timeout=10000"; "PRAGMA temp_store=MEMORY"; ] in

  let journal_mode =
    let query_stmt = prepare src "PRAGMA journal_mode" in
      let () = reset query_stmt |> or_fail "reset query" in
      match step query_stmt with
        | Rc.ROW -> Data.to_string_exn (column query_stmt 0)
        | err -> Fmt.failwith "Sqlite3 page_size error: %s" (Rc.to_string err) in

  let page_size =
    let query_stmt = prepare src "PRAGMA page_size" in
      let () = reset query_stmt |> or_fail "reset query" in
      match step query_stmt with
        | Rc.ROW -> Data.to_int_exn (column query_stmt 0)
        | err -> Fmt.failwith "Sqlite3 page_size error: %s" (Rc.to_string err) in

  let () = let st = Unix.stat t_src in
    Fmt.pr "Source database is %i KB" (st.st_size / 1024) in

  let () =
    match journal_mode with
      | "wal" ->
        let st = Unix.stat (t_src ^ "-wal") in
          let wal_pages = (min st.st_size (1024 * 1024 * 1024)) / page_size in
            if wal_pages > 2000 then begin
              let sql = "PRAGMA cache_size=" ^ (string_of_int wal_pages) in
                exec src sql |> or_fail sql
            end ;
         Fmt.pr " plus %i KB WAL\n" (st.st_size / 1024)
      | _ -> Fmt.pr "\n" in

  let dst = db_open t_dst in

  let () = List.iter ( fun sql -> exec dst sql |> or_fail sql )
  [ "PRAGMA synchronous=OFF"; "PRAGMA journal_mode=TRUNCATE"; "PRAGMA temp_store=MEMORY"; "PRAGMA cache_size=1"; ] in

  let backup = (Backup.init ~dst ~dst_name:"main" ~src ~src_name:"main") in

  let () = (Backup.step backup 0 |> or_fail "backup step") in

  let () = Fmt.pr "Backing up %i pages from %s\n" (Backup.remaining backup) t_src in

  let start = Unix.gettimeofday () in

  let () =
    let rec run () = match (Backup.step backup (-1)) with
      | Rc.LOCKED -> Unix.sleep 10; run ()
      | Rc.BUSY -> run ()
      | Rc.DONE -> ()
      | err -> Fmt.pr "Sqlite3 error: %s" (Rc.to_string err)
      in run () in

  let stop = Unix.gettimeofday () in

  let () = Fmt.pr "Backup up %i pages to %s in %f seconds\n" (Backup.pagecount backup) t_dst (stop -. start) in

  let () = (Backup.finish backup |> or_fail "backup finished") in

  let () = exec dst ("PRAGMA journal_mode=" ^ journal_mode) |> or_fail "failed to set journal_mode" in

  let () = if not (db_close src && db_close dst) then
    Fmt.failwith "Sqlite3 close error" in

  ()

let source =
  let doc = "Source database file to backup." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"SOURCE" ~doc)

let destination =
  let doc = "Database file to backup to." in
  Arg.(required & pos 1 (some string) None & info [] ~docv:"DESTINATION" ~doc)

let sqlite_backup_t = Term.(const sqlite_backup $ source $ destination)

let cmd =
  let doc = "Backup a SQLite database." in
  let man = [
    `S Manpage.s_bugs;
    `P "Email bug reports to <mark@tarides.com>." ]
  in
  let info = Cmd.info "sqlite3-backup" ~version:"%%VERSION%%" ~doc ~man in
  Cmd.v info sqlite_backup_t

let main () = exit (Cmd.eval cmd)
let () = main ()

