# Changelog

## [0.3.0](https://github.com/koki-develop/cubby/compare/v0.2.0...v0.3.0) (2026-09-08)


### Features

* Give the tool a --version flag ([69cbbd2](https://github.com/koki-develop/cubby/commit/69cbbd23db5e17ada280e2cc4bb6b92f6ef29f1c))

## [0.2.0](https://github.com/koki-develop/cubby/compare/v0.1.0...v0.2.0) (2026-09-07)


### ⚠ BREAKING CHANGES

* `cubby set <name>` no longer overwrites an existing secret; pass `--force` to replace one.

### Features

* Refuse to overwrite an existing secret unless --force is passed ([293dab9](https://github.com/koki-develop/cubby/commit/293dab9d3d4d1da506579791f003ac0ca2c3bf3c))
* Release v0.1.1 ([539059a](https://github.com/koki-develop/cubby/commit/539059a6b3310623e8ad85b817d37d69e04286d3))
* Release v0.2.0 ([94661a7](https://github.com/koki-develop/cubby/commit/94661a72cf9a432606757de57e98fa62b064429b))

## 0.1.0 (2026-09-07)


### Features

* Add CLI skeleton ([eb5fa13](https://github.com/koki-develop/cubby/commit/eb5fa134bed253b7896a4711bc18b839efe65e61))
* Implement secret storage backed by the Secure Enclave ([df03c94](https://github.com/koki-develop/cubby/commit/df03c9460bf3ddba74cf4f05dd43e3c4c1fb5f93))
* Release v0.1.0 ([b876594](https://github.com/koki-develop/cubby/commit/b876594e59c74795c21c9bad91277873dba14798))
* Say what the Touch ID prompt is about to do, and whether it replaces ([3b1bc1d](https://github.com/koki-develop/cubby/commit/3b1bc1dcbc50702eedc7016d9081d722dd3a830b))


### Bug Fixes

* Check for an enrolled biometry before creating the store key ([d7530d1](https://github.com/koki-develop/cubby/commit/d7530d1d8ed4c5e5e2f59a4e1b16bfd666caf56d))
