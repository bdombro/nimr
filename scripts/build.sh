nimble install -y --depsOnly
nim c -d:release --hints:off --verbosity:0 -o:dist/nimr nimr.nim