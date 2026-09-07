# cubby

[![GitHub Release](https://img.shields.io/github/v/release/koki-develop/cubby?style=flat-square)](https://github.com/koki-develop/cubby/releases/latest)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/koki-develop/cubby/ci.yml?style=flat-square&logo=github)](https://github.com/koki-develop/cubby/actions/workflows/ci.yml)
[![GitHub License](https://img.shields.io/github/license/koki-develop/cubby?style=flat-square)](./LICENSE)

A macOS CLI that keeps secrets on disk, encrypted under a Secure Enclave key gated by Touch ID.

The key lives in the Secure Enclave and never exists outside it, so saving or reading a secret always costs one Touch ID prompt.

## Requirements

- macOS 14 or later, on Apple silicon
- Touch ID enrolled

## Installation

```sh
brew install koki-develop/tap/cubby
```

## Usage

Create the store once:

```sh
cubby init
```

Save a secret. The value is read from the terminal with echo off:

```sh
cubby set my-secret
cubby set my-secret --from-stdin  # read the value from standard input instead
cubby set my-secret --force       # replace the value already stored
```

Read one back:

```sh
cubby get my-secret
```

List and delete:

```sh
cubby list
cubby rm my-secret
```

## Storage

The store lives at `~/.cubby`, or at `$CUBBY_HOME` when that is set:

```
~/.cubby/                (0700)
├── key.blob             wrapped Secure Enclave key   (0600)
└── secrets/
    └── <hex>.bin        one secret                   (0600)
```

Secrets are sealed with HPKE (P-256 / SHA-256 / AES-GCM-256).

`key.blob` only unwraps inside the Secure Enclave that created it, so a copy of the store is unreadable on any other Mac.

## License

[MIT](./LICENSE)
