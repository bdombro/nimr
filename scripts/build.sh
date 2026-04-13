nimble install -y --depsOnly
nimble setup
nim c -d:release --hints:off --verbosity:0 -o:dist/nimr nimr.nim