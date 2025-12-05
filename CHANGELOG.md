## [1.3.2](https://github.com/wetransform/hk-config/compare/v1.3.1...v1.3.2) (2025-12-05)

### Bug Fixes

* respect .gitleaks.toml file if present ([7ec78b1](https://github.com/wetransform/hk-config/commit/7ec78b1ee0de8f34c146cb1768fcf2f5bb9ff197))

## [1.3.1](https://github.com/wetransform/hk-config/compare/v1.3.0...v1.3.1) (2025-12-05)

### Bug Fixes

* restrict gitleaks scan to files to check ([00f9e62](https://github.com/wetransform/hk-config/commit/00f9e6274202a049dd2aa8129c2f844841b68c75))

## [1.3.0](https://github.com/wetransform/hk-config/compare/v1.2.0...v1.3.0) (2025-12-04)

### Features

* add definition for trivy secret scanning step ([1e206f1](https://github.com/wetransform/hk-config/commit/1e206f111ad05eee992e4551e10887e9e0b5a311))
* add hk test to checks ([addfe3e](https://github.com/wetransform/hk-config/commit/addfe3e97358ee13b5830a56f07981afd8155bf3))
* add pkl formatting step to default configuration ([3367f1e](https://github.com/wetransform/hk-config/commit/3367f1e1e02aefe5011319a4ec0a8e528c0a63f2))
* include secret scan in default configuration ([7d7f289](https://github.com/wetransform/hk-config/commit/7d7f289dbf7da29f351e3ffbc7c8cd091e12b37c))
* use mise exec to run most steps ([fd617cd](https://github.com/wetransform/hk-config/commit/fd617cd2252fad5c04e6ef315bf7e135d73b6c66))

### Bug Fixes

* **deps:** update hk to 1.25.0 ([3b6d491](https://github.com/wetransform/hk-config/commit/3b6d491275c1df4f931aee7235656cf897654efc))
* disable batch processing for prettier step ([2e9bcc1](https://github.com/wetransform/hk-config/commit/2e9bcc195345fac5dd27babaf9e674a77a9399b1))
* fix pkl formatting staging and use pre-define pkl step ([a09dc22](https://github.com/wetransform/hk-config/commit/a09dc228fabd4f716f280988401d0272e03461e4))
* use builtin step for pkl formatting ([faa12e7](https://github.com/wetransform/hk-config/commit/faa12e76dcfa443df291740170c4c7781fe55f8d))
