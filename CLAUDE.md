# CLAUDE.md

`cubby` is a macOS CLI that stores secrets on disk encrypted under a Secure Enclave key gated by Touch ID.

## Commands

```sh
swift build
swift test
swift run cubby <subcommand>
mise bootstrap                 # install the lefthook git hooks (once per clone)
betterleaks git                # secret scan, same command CI runs
```

`CUBBY_HOME` overrides the store root (default `~/.cubby`). **Always set it when exercising the CLI** — otherwise you write into the user's real store. Point it at a directory you can throw away:

```sh
CUBBY_HOME=<scratch dir> swift run cubby init
CUBBY_HOME=<scratch dir> swift run cubby list
```

`set` and `get` block on a real Touch ID prompt and cannot be exercised non-interactively; `init`, `list`, and `rm` can. Don't add flows that assume the prompt can be automated or skipped.

## Architecture

Files under `Sources/cubby/`, each owning one boundary:

- **`Cubby.swift`** — subcommands and `CubbyError`, whose `description` is the message the user sees. Error text is lowercase, no trailing period, phrased as `could not <action>`. A subcommand conforms to `StoreCommand` and does its work in `run(in:to:)`; the default `run()` is the one place that reaches for the process environment and standard output.
- **`Output.swift`** — where a command's output goes. `line` swallows a failed write the way `print` does; `write` reports one, which is what `get` needs for a binary payload.
- **`Enclave.swift`** — the only file that touches `SecureEnclave`/`LocalAuthentication`. `unsupported` is the precondition a store needs — an enclave *and* an enrolled biometry — and `generateKey` reports it rather than letting the key be refused under a bare authentication failure. `restoreKey` builds the key and the `LAContext` but does **not** authenticate; the Touch ID prompt fires later, inside `Record.seal`/`Record.open`, when HPKE first uses the private key. `context.localizedReason` must be set before that point.
- **`Record.swift`** — the on-disk format: `encapsulatedKey (65 bytes) ‖ ciphertext`, HPKE P256/SHA256/AES-GCM-256 in **authentication mode** with the enclave key as both sender and recipient. The `info` string `cubby/v1:<name>` binds a record to its name, so a record moved to another name fails to open. Changing the suite, the info prefix, or the encapsulated-key size breaks every existing store.
- **`SecretName.swift`** — the validated name, and the *only* thing that maps a name to a file: `encoded` is lowercase hex of the name's bytes. The filesystem never sees a user-supplied character, which is what removes path traversal, dotfiles, and case/normalization collisions. Never build a path from raw name text.
- **`Store.swift`** — layout (`$CUBBY_HOME/key.blob`, `$CUBBY_HOME/secrets/<hex>.bin`, both 0600 under a 0700 root) and all filesystem I/O. A `Store` is a value holding its root, and `fromEnvironment` is the only thing that reads `CUBBY_HOME`; pass the store down rather than looking one up. Writes go through `writeAtomically` (tmp sibling → fsync → rename) or `createAtomically`, which answers `false` instead of replacing a file that is already there; use one of them rather than `Data.write`.
- **`Terminal.swift`** — `readpassphrase` on `/dev/tty` with echo off.

## Tests

`Tests/cubbyTests/`. `TestSupport.swift` hands each test its own throwaway store and collects what a command writes; a test never sets an environment variable and never touches the real store.

Anything that needs a real Secure Enclave key is gated on `Enclave.unsupported`, so those tests run on a Mac with Touch ID enrolled and skip elsewhere — a CI runner has an enclave and no biometry to gate a key on.
