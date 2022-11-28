FROM ocaml/opam:debian-11-ocaml-4.14 AS build
RUN sudo apt-get update && sudo apt-get install m4 pkg-config libsqlite3-dev -y --no-install-recommends
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard 56a03100e6d037e7c0e116ed34ec87b11aa3b592 && opam update
COPY --chown=opam sqlite3-backup.opam /src/
WORKDIR /src
RUN opam pin -yn add "git+https://github.com/mtelvers/sqlite3-ocaml#fix-backup"
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/sqlite3-backup

FROM debian:11
RUN apt-get update && apt-get install libsqlite3-dev -y --no-install-recommends
WORKDIR /usr/local/bin
ENTRYPOINT ["/usr/local/bin/sqlite3-backup"]
COPY --from=build /src/_build/install/default/bin/sqlite3-backup /usr/local/bin/
