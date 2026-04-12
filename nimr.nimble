version = "0.1.0"
author = "Brian Dombroski"
description = "Single-file Nim runner with content-hash cache and safe temp filenames"
license = "MIT"

bin = @["nimr"]

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
