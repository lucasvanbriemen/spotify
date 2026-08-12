// Maps the importmap's bare "karaoke/*" specifiers onto
// app/javascript/karaoke/*.js so the modules run under plain node exactly as
// written in the browser. Passed via --import (see bin/test-js); the test
// runner propagates it to every test file's process.
import { register } from "node:module"

register(new URL("./karaoke_loader.mjs", import.meta.url))
