# [1.24.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.23.3...v1.24.0) (2026-02-09)


### Features

* add rake task to generate schema without server ([#260](https://github.com/ForestAdmin/agent-ruby/issues/260)) ([1ee7189](https://github.com/ForestAdmin/agent-ruby/commit/1ee7189cd526698cefb5f25c033c26a503c92f85))

## [1.23.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.23.2...v1.23.3) (2026-02-09)


### Bug Fixes

* **apimap:** log error on post apimap failure ([#262](https://github.com/ForestAdmin/agent-ruby/issues/262)) ([d309621](https://github.com/ForestAdmin/agent-ruby/commit/d309621deeb94c015280d7ef1bf2c6d01bd8465e))

## [1.23.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.23.1...v1.23.2) (2026-02-06)


### Bug Fixes

* **ci:** use BUNDLE_PATH to avoid insecure install path with Ruby 4.0 ([#261](https://github.com/ForestAdmin/agent-ruby/issues/261)) ([fe2bb53](https://github.com/ForestAdmin/agent-ruby/commit/fe2bb53479683981379d4ac9798c8eff11189b89))

## [1.23.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.23.0...v1.23.1) (2026-01-28)


### Bug Fixes

* **context_variables:** update tags parsing to match API v4 response format ([#258](https://github.com/ForestAdmin/agent-ruby/issues/258)) ([57b913d](https://github.com/ForestAdmin/agent-ruby/commit/57b913df3e5f735cdc54bcf6ae2ed2db05a43372))

# [1.23.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.22.3...v1.23.0) (2026-01-26)


### Features

* **rpc agent:** add mark collection as rpc option on add datasource ([#256](https://github.com/ForestAdmin/agent-ruby/issues/256)) ([fc9e129](https://github.com/ForestAdmin/agent-ruby/commit/fc9e1294273b63ace870ebf43b21cdbe4850cce0))

## [1.22.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.22.2...v1.22.3) (2026-01-23)


### Bug Fixes

* **rpcagent:** symbolize params keys in base route ([#254](https://github.com/ForestAdmin/agent-ruby/issues/254)) ([54ba34a](https://github.com/ForestAdmin/agent-ruby/commit/54ba34aa35b426997eca021bbcbfbf2bd420c6d6))

## [1.22.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.22.1...v1.22.2) (2026-01-22)


### Bug Fixes

* **projection:** return proper bad request error on unknown fields ([#253](https://github.com/ForestAdmin/agent-ruby/issues/253)) ([2fa23a7](https://github.com/ForestAdmin/agent-ruby/commit/2fa23a74c377a1dc7aa0a1d4382501e2251b28fa))

## [1.22.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.22.0...v1.22.1) (2026-01-13)


### Bug Fixes

* **rpc:** cleanly log tcp error on rpc polling ([#251](https://github.com/ForestAdmin/agent-ruby/issues/251)) ([32a9e3f](https://github.com/ForestAdmin/agent-ruby/commit/32a9e3f6dc5679eb132b10b0dc8c2df9c9cd1cb1))

# [1.22.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.21.0...v1.22.0) (2026-01-08)


### Features

* add ruby 4.0.0 support ([#250](https://github.com/ForestAdmin/agent-ruby/issues/250)) ([ac30fe7](https://github.com/ForestAdmin/agent-ruby/commit/ac30fe7c749c81b9c0cd72e4ea4eab2964f223fe))

# [1.21.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.20.0...v1.21.0) (2026-01-07)


### Features

* support polymorphic relations in collection renaming ([#244](https://github.com/ForestAdmin/agent-ruby/issues/244)) ([1ee1251](https://github.com/ForestAdmin/agent-ruby/commit/1ee12517b2c625f7aeaca937ecda092ea7737281))

# [1.20.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.19.3...v1.20.0) (2026-01-07)


### Features

* handle rpc relations ([#240](https://github.com/ForestAdmin/agent-ruby/issues/240)) ([c8fb188](https://github.com/ForestAdmin/agent-ruby/commit/c8fb1889df87712d5bf0bbdfd6ab630c0b2f0c21))

## [1.19.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.19.2...v1.19.3) (2026-01-05)


### Performance Improvements

* improve array/hash operation ([#247](https://github.com/ForestAdmin/agent-ruby/issues/247)) ([9ca00fc](https://github.com/ForestAdmin/agent-ruby/commit/9ca00fc8b765a6a3dd5c09cddb50aa2d48eafd22))

## [1.19.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.19.1...v1.19.2) (2026-01-05)


### Performance Improvements

* improve memory and cpu usage ([#248](https://github.com/ForestAdmin/agent-ruby/issues/248)) ([67a16c5](https://github.com/ForestAdmin/agent-ruby/commit/67a16c5a9dd4e11f03eb0f0b23d1f8739ca3b198))

## [1.19.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.19.0...v1.19.1) (2025-12-24)


### Bug Fixes

* **composite datasource:** improve perf on collection exist check ([#246](https://github.com/ForestAdmin/agent-ruby/issues/246)) ([afd4481](https://github.com/ForestAdmin/agent-ruby/commit/afd4481bbe4a59626ee5940a366f41a68eea9f4f))

# [1.19.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.18.3...v1.19.0) (2025-12-24)


### Features

* sort filter operators alphabetically in rpc schema ([#245](https://github.com/ForestAdmin/agent-ruby/issues/245)) ([a584df8](https://github.com/ForestAdmin/agent-ruby/commit/a584df807cdc234102fd007d23baa925c14b241c))

## [1.18.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.18.2...v1.18.3) (2025-12-22)


### Bug Fixes

* **schema-polling:** improve polling ([#237](https://github.com/ForestAdmin/agent-ruby/issues/237)) ([cf07ed4](https://github.com/ForestAdmin/agent-ruby/commit/cf07ed4bf36c316272e350cdaa5e10f27f1d65d9))

## [1.18.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.18.1...v1.18.2) (2025-12-12)


### Bug Fixes

* **rpc:** allow agent startup with introspection only ([#238](https://github.com/ForestAdmin/agent-ruby/issues/238)) ([a8cc791](https://github.com/ForestAdmin/agent-ruby/commit/a8cc791db8240cdac3657c0d8bc21c22bc8ce535))

## [1.18.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.18.0...v1.18.1) (2025-12-11)


### Bug Fixes

* **dsl:** support form_value in dynamic form field procs ([#239](https://github.com/ForestAdmin/agent-ruby/issues/239)) ([5d7625e](https://github.com/ForestAdmin/agent-ruby/commit/5d7625e78d7ff5f965df9ecb7aedb3e2009187ee))

# [1.18.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.17.0...v1.18.0) (2025-12-11)


### Features

* **rpc:** replace sse with polling  ([#235](https://github.com/ForestAdmin/agent-ruby/issues/235)) ([af7231b](https://github.com/ForestAdmin/agent-ruby/commit/af7231b6a3e0d9a04ca358c5a87fd521b54d3ccf))

# [1.17.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.10...v1.17.0) (2025-12-11)


### Features

* **dsl:** add dynamic forms support with proc-based properties ([#233](https://github.com/ForestAdmin/agent-ruby/issues/233)) ([7f00984](https://github.com/ForestAdmin/agent-ruby/commit/7f009842428d45c7165b35b087b5b12a988cd084))

## [1.16.10](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.9...v1.16.10) (2025-12-09)


### Bug Fixes

* extended search ([#227](https://github.com/ForestAdmin/agent-ruby/issues/227)) ([a7bc6ee](https://github.com/ForestAdmin/agent-ruby/commit/a7bc6ee14d3e885d7c483601fbf53e597a969f0e))

## [1.16.9](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.8...v1.16.9) (2025-12-08)


### Bug Fixes

* delay value validation when templating ([#226](https://github.com/ForestAdmin/agent-ruby/issues/226)) ([3df4ee9](https://github.com/ForestAdmin/agent-ruby/commit/3df4ee949fd5eef6245d77a37b8e719ca19c6b8b))

## [1.16.8](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.7...v1.16.8) (2025-12-05)


### Bug Fixes

* agent use plugin ([#225](https://github.com/ForestAdmin/agent-ruby/issues/225)) ([cb70a92](https://github.com/ForestAdmin/agent-ruby/commit/cb70a9257daae80c48760180f58a5abd29e999f7))

## [1.16.7](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.6...v1.16.7) (2025-12-05)


### Bug Fixes

* **activerecord:** ignore attribue fields ([#223](https://github.com/ForestAdmin/agent-ruby/issues/223)) ([be16f2a](https://github.com/ForestAdmin/agent-ruby/commit/be16f2acd5ac392dc136b3105733b41bbb9f603a))

## [1.16.6](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.5...v1.16.6) (2025-12-05)


### Bug Fixes

* prevent routes loading when agent not instantiated ([#224](https://github.com/ForestAdmin/agent-ruby/issues/224)) ([b9b1e42](https://github.com/ForestAdmin/agent-ruby/commit/b9b1e4211759e44d1d39da2b6d96ee66a3571416))

## [1.16.5](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.4...v1.16.5) (2025-12-04)


### Bug Fixes

* **rpc:** ensure single SSE connection to master ([#222](https://github.com/ForestAdmin/agent-ruby/issues/222)) ([c7b65e9](https://github.com/ForestAdmin/agent-ruby/commit/c7b65e9cad3157bf2335a30e407b3035620b0c1a))

## [1.16.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.3...v1.16.4) (2025-12-04)


### Bug Fixes

* handle field validations ([#220](https://github.com/ForestAdmin/agent-ruby/issues/220)) ([82f9711](https://github.com/ForestAdmin/agent-ruby/commit/82f971110ae8d7a9a58d5e48a655b37efbb0f008))

## [1.16.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.2...v1.16.3) (2025-12-04)


### Bug Fixes

* **rpc:** properly cleanup SSE connections and handle shutdown signals ([#218](https://github.com/ForestAdmin/agent-ruby/issues/218)) ([a5b306c](https://github.com/ForestAdmin/agent-ruby/commit/a5b306c1852f384e4b2a38eae216b24ef903a830))

## [1.16.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.1...v1.16.2) (2025-12-04)


### Bug Fixes

* handle polymorphic many-to-one relations in create and update operations ([#217](https://github.com/ForestAdmin/agent-ruby/issues/217)) ([e2d2016](https://github.com/ForestAdmin/agent-ruby/commit/e2d20167cee0ce993d8861f98f4f22652ade3b41))

## [1.16.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.16.0...v1.16.1) (2025-12-03)


### Bug Fixes

* improve error handling for non-existent collections with proper HTTP 404 ([#215](https://github.com/ForestAdmin/agent-ruby/issues/215)) ([4be7b2b](https://github.com/ForestAdmin/agent-ruby/commit/4be7b2bab3407cd3a532ba1968527c551839efb7))

# [1.16.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.15.2...v1.16.0) (2025-12-02)


### Features

* add DSL for easier agent customization ([#208](https://github.com/ForestAdmin/agent-ruby/issues/208)) ([93e08d8](https://github.com/ForestAdmin/agent-ruby/commit/93e08d805a574bd8b46267c95734d4d9557fc838))

## [1.15.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.15.1...v1.15.2) (2025-11-28)


### Bug Fixes

* ignore forest_admin directory in zeitwerk loader ([#214](https://github.com/ForestAdmin/agent-ruby/issues/214)) ([59606c7](https://github.com/ForestAdmin/agent-ruby/commit/59606c7f702a0055f0c8b297281fc0b153343fa3))

## [1.15.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.15.0...v1.15.1) (2025-11-26)


### Bug Fixes

* auto-create virtual models for HABTM join tables with id column ([#213](https://github.com/ForestAdmin/agent-ruby/issues/213)) ([bd523e8](https://github.com/ForestAdmin/agent-ruby/commit/bd523e884b5a526186acfed7cd6839b1af7e5ce6))

# [1.15.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.14.4...v1.15.0) (2025-11-26)


### Features

* export Forest Admin types as a single module ([#212](https://github.com/ForestAdmin/agent-ruby/issues/212)) ([b1b771e](https://github.com/ForestAdmin/agent-ruby/commit/b1b771e30003f9796b992a0d56822cf2d283c6b7))

## [1.14.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.14.3...v1.14.4) (2025-11-25)


### Bug Fixes

* prevent error accessing foreign_collection on polymorphic relations ([#211](https://github.com/ForestAdmin/agent-ruby/issues/211)) ([3d98753](https://github.com/ForestAdmin/agent-ruby/commit/3d98753a7fbf42bdf97869e652e57a62828a3ebe))

## [1.14.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.14.2...v1.14.3) (2025-11-14)


### Bug Fixes

* **rpc_route:** align health check with forest_admin_agent behavior ([#210](https://github.com/ForestAdmin/agent-ruby/issues/210)) ([1e2746a](https://github.com/ForestAdmin/agent-ruby/commit/1e2746ae2ddfdcee7c8140bb559a93b45c77d709))

## [1.14.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.14.1...v1.14.2) (2025-11-12)


### Bug Fixes

* handle errors gracefully when processing active record associations ([#209](https://github.com/ForestAdmin/agent-ruby/issues/209)) ([ee146a4](https://github.com/ForestAdmin/agent-ruby/commit/ee146a4a34916d6e2ee7ae3d2244d4b43acae71a))

## [1.14.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.14.0...v1.14.1) (2025-11-07)


### Bug Fixes

* add polymorphic type filter for has_many :through associations ([#206](https://github.com/ForestAdmin/agent-ruby/issues/206)) ([2e83084](https://github.com/ForestAdmin/agent-ruby/commit/2e830843761e91695e33ce5dadb88b7e1851af1b))

# [1.14.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.13.4...v1.14.0) (2025-11-07)


### Features

* add caching routes for rpc agent ([#207](https://github.com/ForestAdmin/agent-ruby/issues/207)) ([c142370](https://github.com/ForestAdmin/agent-ruby/commit/c142370ba7303289bb697dbbb7b063d149f23b5c))

## [1.13.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.13.3...v1.13.4) (2025-11-06)


### Bug Fixes

* **rpc:** parse rpc caller + routes + cache ([#204](https://github.com/ForestAdmin/agent-ruby/issues/204)) ([51d7ae7](https://github.com/ForestAdmin/agent-ruby/commit/51d7ae72b8a4a81a568c71f910890ad8951b4579))

## [1.13.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.13.2...v1.13.3) (2025-11-05)


### Bug Fixes

* prevent NoMethodError on polymorphic associations with pending migrations ([#203](https://github.com/ForestAdmin/agent-ruby/issues/203)) ([bbe89c9](https://github.com/ForestAdmin/agent-ruby/commit/bbe89c93bf98cbea8a257277c5df84450b3ecaca))

## [1.13.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.13.1...v1.13.2) (2025-11-04)


### Bug Fixes

* **rpc:** handle multi stack connection ([#177](https://github.com/ForestAdmin/agent-ruby/issues/177)) ([77938fc](https://github.com/ForestAdmin/agent-ruby/commit/77938fc03a26c0946cd60bf0b1dc0b48c44f0379))

## [1.13.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.13.0...v1.13.1) (2025-11-03)


### Bug Fixes

* **rpcAgent:** circular dependency on install command ([#200](https://github.com/ForestAdmin/agent-ruby/issues/200)) ([57f8828](https://github.com/ForestAdmin/agent-ruby/commit/57f88282991fd4b24e4ba81119f9fd9225cd8768))

# [1.13.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.16...v1.13.0) (2025-10-31)


### Features

* **nativeQueries:** support for union queries ([#199](https://github.com/ForestAdmin/agent-ruby/issues/199)) ([6408a39](https://github.com/ForestAdmin/agent-ruby/commit/6408a39bb37632719d02893829d0744dfdccf426))

## [1.12.16](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.15...v1.12.16) (2025-10-30)


### Bug Fixes

* **auth:** store config in container without TTL to prevent expiration ([#198](https://github.com/ForestAdmin/agent-ruby/issues/198)) ([7ffd20c](https://github.com/ForestAdmin/agent-ruby/commit/7ffd20ccb67a94db4dba6c543ac2da96aaa6c0b4))

## [1.12.15](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.14...v1.12.15) (2025-10-29)


### Bug Fixes

* **routesCache:** set route context as stateless to avoid concurrency issues ([#196](https://github.com/ForestAdmin/agent-ruby/issues/196)) ([c0a834a](https://github.com/ForestAdmin/agent-ruby/commit/c0a834a8970dd754aa3c62146925228489d5dc18))

## [1.12.14](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.13...v1.12.14) (2025-10-29)


### Bug Fixes

* safely load id for many-to-one relationships ([#195](https://github.com/ForestAdmin/agent-ruby/issues/195)) ([ae8d4d7](https://github.com/ForestAdmin/agent-ruby/commit/ae8d4d7acb983d0ed61c5dd27ac23b5ea75c21cd))

## [1.12.13](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.12...v1.12.13) (2025-10-29)


### Bug Fixes

* better error handling ([#173](https://github.com/ForestAdmin/agent-ruby/issues/173)) ([42c9174](https://github.com/ForestAdmin/agent-ruby/commit/42c9174dda231f4d0803c7f0ee161538041b0dde))

## [1.12.12](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.11...v1.12.12) (2025-10-29)


### Bug Fixes

* **routesCaching:** ensure routes for plugin customizations are mounted and cached ([#190](https://github.com/ForestAdmin/agent-ruby/issues/190)) ([1491f25](https://github.com/ForestAdmin/agent-ruby/commit/1491f253eecf1674742916ae40e786c5acf2ec52))

## [1.12.11](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.10...v1.12.11) (2025-10-29)


### Bug Fixes

* **errorMessage:** better field handling ([#192](https://github.com/ForestAdmin/agent-ruby/issues/192)) ([b898b36](https://github.com/ForestAdmin/agent-ruby/commit/b898b36fbd6130f937a2b9b26bdb87434572e9d4))

## [1.12.10](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.9...v1.12.10) (2025-10-28)


### Bug Fixes

* **schema:** field type for array definition ([#191](https://github.com/ForestAdmin/agent-ruby/issues/191)) ([39ef7fb](https://github.com/ForestAdmin/agent-ruby/commit/39ef7fbe934df6ee58d47a91a1c3d5c08f18972d))

## [1.12.9](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.8...v1.12.9) (2025-10-27)


### Bug Fixes

* handle properly composite datasource ([#179](https://github.com/ForestAdmin/agent-ruby/issues/179)) ([b63f39a](https://github.com/ForestAdmin/agent-ruby/commit/b63f39ae38d7c088494b7abf9237d0597cce5be9))

## [1.12.8](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.7...v1.12.8) (2025-10-27)


### Bug Fixes

* **config:** add setting to disable route cache ([#189](https://github.com/ForestAdmin/agent-ruby/issues/189)) ([5acf768](https://github.com/ForestAdmin/agent-ruby/commit/5acf7686ca141c02facc2260181a45d13716e19c))

## [1.12.7](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.6...v1.12.7) (2025-10-27)


### Bug Fixes

* **filters:** operators now try to parse the value into the field's type before comparing the values ([#188](https://github.com/ForestAdmin/agent-ruby/issues/188)) ([b0dd9b9](https://github.com/ForestAdmin/agent-ruby/commit/b0dd9b9486932e5e49765c811c8011c6f0f606c8))

## [1.12.6](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.5...v1.12.6) (2025-10-27)


### Bug Fixes

* **datasource:** list related has many without constraint ([#185](https://github.com/ForestAdmin/agent-ruby/issues/185)) ([2347dff](https://github.com/ForestAdmin/agent-ruby/commit/2347dffe75a2fd323aab1d65735bd88e9f46deec))

## [1.12.5](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.4...v1.12.5) (2025-10-24)


### Bug Fixes

* skip ForestAdmin initialization during rake tasks ([#184](https://github.com/ForestAdmin/agent-ruby/issues/184)) ([c9a1be7](https://github.com/ForestAdmin/agent-ruby/commit/c9a1be7ea0384216474da2f3dff2b9d931db338a))

## [1.12.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.3...v1.12.4) (2025-10-24)


### Bug Fixes

* ruby 3.4+ compatibility gems to gemspecs ([#183](https://github.com/ForestAdmin/agent-ruby/issues/183)) ([ea0b118](https://github.com/ForestAdmin/agent-ruby/commit/ea0b11861eeca8dc4b650d03166757c8599c1b49))

## [1.12.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.2...v1.12.3) (2025-10-23)


### Bug Fixes

* **collection:** related data query on non id foreign key ([#178](https://github.com/ForestAdmin/agent-ruby/issues/178)) ([b76ca4c](https://github.com/ForestAdmin/agent-ruby/commit/b76ca4c6ffc8ff0a7e190bbb246ad2de01aab2ef))

## [1.12.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.1...v1.12.2) (2025-10-23)


### Bug Fixes

* move create_agent files to lib directory for consistency ([#180](https://github.com/ForestAdmin/agent-ruby/issues/180)) ([0a26cfd](https://github.com/ForestAdmin/agent-ruby/commit/0a26cfd351fb48efa61d543a77c3c1f30ec8126d))

## [1.12.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.12.0...v1.12.1) (2025-10-23)


### Performance Improvements

* add route caching to avoid recomputing routes on every request ([#163](https://github.com/ForestAdmin/agent-ruby/issues/163)) ([2b21410](https://github.com/ForestAdmin/agent-ruby/commit/2b214100056af48b5f028353903349d027a08a3c))

# [1.12.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.11.4...v1.12.0) (2025-10-23)


### Features

* **cors:** allow to disable forest_admin_rails cors ([#176](https://github.com/ForestAdmin/agent-ruby/issues/176)) ([70700e8](https://github.com/ForestAdmin/agent-ruby/commit/70700e88770e438ae170f8d6dc1c1e39f412e27b))

## [1.11.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.11.3...v1.11.4) (2025-10-22)


### Bug Fixes

* add primary key validation for smart actions ([#167](https://github.com/ForestAdmin/agent-ruby/issues/167)) ([1ec00d9](https://github.com/ForestAdmin/agent-ruby/commit/1ec00d99395a7479110d034672ccb111be884dfd))
* optimize queries for has-many relationships ([#170](https://github.com/ForestAdmin/agent-ruby/issues/170)) ([b931294](https://github.com/ForestAdmin/agent-ruby/commit/b931294ceb93bf02a16fdb37893fd127c077c1b1))

## [1.11.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.11.2...v1.11.3) (2025-10-22)


### Bug Fixes

* **engine:** prevent agent setup on non-server Rails commands ([#172](https://github.com/ForestAdmin/agent-ruby/issues/172)) ([2e9c701](https://github.com/ForestAdmin/agent-ruby/commit/2e9c701da0de19b60fbcfaaf9593b163e4a3dd1e))

## [1.11.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.11.1...v1.11.2) (2025-10-22)


### Bug Fixes

* **engine:** skip create agent setup when not running rails server ([#166](https://github.com/ForestAdmin/agent-ruby/issues/166)) ([81b5142](https://github.com/ForestAdmin/agent-ruby/commit/81b5142eca3a988d89e176bfc1df69350b6e0545))
* **projection:** add polymorphic_type column if not requested ([#171](https://github.com/ForestAdmin/agent-ruby/issues/171)) ([3ee1251](https://github.com/ForestAdmin/agent-ruby/commit/3ee1251fdd521da93e05b908dcded5958c596e36))

## [1.11.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.11.0...v1.11.1) (2025-10-21)


### Bug Fixes

* remove 🌳🌳🌳 from error messages ([#165](https://github.com/ForestAdmin/agent-ruby/issues/165)) ([339e38f](https://github.com/ForestAdmin/agent-ruby/commit/339e38f94d65fc0ca40a4c1d68349bac696fe746))

# [1.11.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.10.0...v1.11.0) (2025-10-21)


### Features

* csv streaming ([#155](https://github.com/ForestAdmin/agent-ruby/issues/155)) ([a6f03af](https://github.com/ForestAdmin/agent-ruby/commit/a6f03af7a98468d6e8977347e627e8a56d4853e2))

# [1.10.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.9.1...v1.10.0) (2025-10-21)


### Features

* **routes:** add new update field route to update unique hasMany relation ([#161](https://github.com/ForestAdmin/agent-ruby/issues/161)) ([053690e](https://github.com/ForestAdmin/agent-ruby/commit/053690e1b22b72b9e6b4a6e05348fecc96dbaffa))

## [1.9.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.9.0...v1.9.1) (2025-10-21)


### Bug Fixes

* error handling on ip-whitelist-rules call ([#162](https://github.com/ForestAdmin/agent-ruby/issues/162)) ([2837547](https://github.com/ForestAdmin/agent-ruby/commit/2837547012cb90cc591b3c92e9001f04a8b9aa5a))

# [1.9.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.9...v1.9.0) (2025-10-20)


### Features

* **agent options:** allow to skip schema update ([#160](https://github.com/ForestAdmin/agent-ruby/issues/160)) ([80cf2bd](https://github.com/ForestAdmin/agent-ruby/commit/80cf2bdb470aa57fd9c9da769319bfa2b52c6315))

## [1.8.9](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.8...v1.8.9) (2025-10-20)


### Bug Fixes

* permission check crash on refetch ([#157](https://github.com/ForestAdmin/agent-ruby/issues/157)) ([8c5d0bc](https://github.com/ForestAdmin/agent-ruby/commit/8c5d0bc87336d9033939e778b9086bf56a541326))
* **security:** SQL injection vulnerability in date truncation ([#158](https://github.com/ForestAdmin/agent-ruby/issues/158)) ([8f52ecd](https://github.com/ForestAdmin/agent-ruby/commit/8f52ecd1c36e09f2dcf8797ebd222935213bb62b))

## [1.8.8](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.7...v1.8.8) (2025-10-20)


### Bug Fixes

* **error-handling:** CRUD errors throw 400 instead of 500 errors and error messages are sent to frontend ([#153](https://github.com/ForestAdmin/agent-ruby/issues/153)) ([1a1c8f3](https://github.com/ForestAdmin/agent-ruby/commit/1a1c8f314d39ebb90afc26402ce930f296b78bb6))
* comparison operators ([#149](https://github.com/ForestAdmin/agent-ruby/issues/149)) ([56900a5](https://github.com/ForestAdmin/agent-ruby/commit/56900a590ae3d26002d63a95834c79abbee6fde5))

## [1.8.7](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.6...v1.8.7) (2025-10-20)


### Bug Fixes

* **list:** removes null values in included records ([#147](https://github.com/ForestAdmin/agent-ruby/issues/147)) ([26cf793](https://github.com/ForestAdmin/agent-ruby/commit/26cf793fbff871a4b482c241d7419082c9e0c421))

## [1.8.6](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.5...v1.8.6) (2025-10-17)


### Bug Fixes

* pagination validation ([#156](https://github.com/ForestAdmin/agent-ruby/issues/156)) ([817e275](https://github.com/ForestAdmin/agent-ruby/commit/817e2751cb590a97c348d9b20ddb4e951cdd9b57))

## [1.8.5](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.4...v1.8.5) (2025-10-17)


### Bug Fixes

* **logs:** remove spam logs about mounted charts ([#152](https://github.com/ForestAdmin/agent-ruby/issues/152)) ([888f073](https://github.com/ForestAdmin/agent-ruby/commit/888f073149df190449a1cbe235b22f6540772b96))

## [1.8.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.3...v1.8.4) (2025-10-17)


### Bug Fixes

* **datasource_activerecord:** implement blank, present & missing filter operators with proper string handling ([#148](https://github.com/ForestAdmin/agent-ruby/issues/148)) ([d69b1dc](https://github.com/ForestAdmin/agent-ruby/commit/d69b1dc55a7316580135be1cf937f25aa6d04abe))

## [1.8.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.2...v1.8.3) (2025-10-14)


### Bug Fixes

* rename loggerLevel to logger_level ([#151](https://github.com/ForestAdmin/agent-ruby/issues/151)) ([79aef9e](https://github.com/ForestAdmin/agent-ruby/commit/79aef9e766a5b79fcf9f6d758892e13c37642c8f))

## [1.8.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.1...v1.8.2) (2025-10-14)


### Bug Fixes

* enable error logging in production mode ([#150](https://github.com/ForestAdmin/agent-ruby/issues/150)) ([34ca626](https://github.com/ForestAdmin/agent-ruby/commit/34ca62661e76ba5c4d954d3b70d38a627467a522))

## [1.8.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.8.0...v1.8.1) (2025-10-13)


### Bug Fixes

* **error handling:** retrieve the error message properly ([#146](https://github.com/ForestAdmin/agent-ruby/issues/146)) ([a696458](https://github.com/ForestAdmin/agent-ruby/commit/a6964587f48433d85c9d8c1124a72f2b9536cef1))

# [1.8.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.7.1...v1.8.0) (2025-10-13)


### Features

* **sse:** implement Sinatra SSE + improvement on connection handling ([#135](https://github.com/ForestAdmin/agent-ruby/issues/135)) ([057b425](https://github.com/ForestAdmin/agent-ruby/commit/057b4255d8b47f33233b14764101da82e4a9df5f))

## [1.7.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.7.0...v1.7.1) (2025-10-13)


### Bug Fixes

* **actions:** use datasource instead of collection in build_field_schema ([413ef78](https://github.com/ForestAdmin/agent-ruby/commit/413ef7817c70585c9581c607924981812df0de7a))

# [1.7.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.6.1...v1.7.0) (2025-10-10)


### Features

* **config:** support FOREST_SERVER_URL environment variable ([#143](https://github.com/ForestAdmin/agent-ruby/issues/143)) ([5e3839a](https://github.com/ForestAdmin/agent-ruby/commit/5e3839a4a7224d70aa7ce804ba5de0df8083d45a))

## [1.6.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.6.0...v1.6.1) (2025-10-10)


### Bug Fixes

* **controller:** simplify forest_controller exception_handler ([#141](https://github.com/ForestAdmin/agent-ruby/issues/141)) ([3a41dd2](https://github.com/ForestAdmin/agent-ruby/commit/3a41dd2914163cb1d8b9c55486bef8bb1c136828))

# [1.6.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.5.0...v1.6.0) (2025-10-08)


### Features

* **caller:** allow extra arguments ([#140](https://github.com/ForestAdmin/agent-ruby/issues/140)) ([b3510c0](https://github.com/ForestAdmin/agent-ruby/commit/b3510c02fcd9dd4456cad41e63370cfe25906d9c))

# [1.5.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.4.1...v1.5.0) (2025-10-06)


### Features

* **rpc_auth:** add millisecond precision to prevent false replay attack detection ([#138](https://github.com/ForestAdmin/agent-ruby/issues/138)) ([7de7c1b](https://github.com/ForestAdmin/agent-ruby/commit/7de7c1ba281f587b41d8d14d3e8dd38d525c2c76))

## [1.4.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.4.0...v1.4.1) (2025-10-03)


### Bug Fixes

* **rpc:** replay attack protection and add thread-safe authentication ([#136](https://github.com/ForestAdmin/agent-ruby/issues/136)) ([4d81c55](https://github.com/ForestAdmin/agent-ruby/commit/4d81c55b420b509416c52e87b7a1ffed32a56dce))

# [1.4.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.3.0...v1.4.0) (2025-10-03)


### Features

* **rpc:** support native query connections ([#134](https://github.com/ForestAdmin/agent-ruby/issues/134)) ([8012557](https://github.com/ForestAdmin/agent-ruby/commit/801255715c56e0f7532dde824c88ff4032c39adb))

# [1.3.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.2.2...v1.3.0) (2025-10-03)


### Features

* **apimap:** allow to merge another forestadmin schema to current ([#129](https://github.com/ForestAdmin/agent-ruby/issues/129)) ([6a01e83](https://github.com/ForestAdmin/agent-ruby/commit/6a01e83f88abafb580de9a5e8e4b8f892e6dacab))

## [1.2.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.2.1...v1.2.2) (2025-10-03)


### Bug Fixes

* **rpc:** forward business errors properly from rpc agent ([#133](https://github.com/ForestAdmin/agent-ruby/issues/133)) ([1b87de6](https://github.com/ForestAdmin/agent-ruby/commit/1b87de660b0825f5abfc5d0ace18c3cdeca4b399))

## [1.2.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.2.0...v1.2.1) (2025-10-03)


### Bug Fixes

* **context:** define setters to update context properties ([#131](https://github.com/ForestAdmin/agent-ruby/issues/131)) ([96053a3](https://github.com/ForestAdmin/agent-ruby/commit/96053a366bf158b000a971c5c284fd000c7a15e7))

# [1.2.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.1.0...v1.2.0) (2025-10-02)


### Features

* **rpc-install:** improve rpc agent customization file ([#132](https://github.com/ForestAdmin/agent-ruby/issues/132)) ([ed2999a](https://github.com/ForestAdmin/agent-ruby/commit/ed2999a197f7a1d0d503b7521b0a6706ee56ef32))

# [1.1.0](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.2...v1.1.0) (2025-10-02)


### Features

* **active-record:** support timestamptz column type ([#130](https://github.com/ForestAdmin/agent-ruby/issues/130)) ([1c2e308](https://github.com/ForestAdmin/agent-ruby/commit/1c2e3080a248a06b1e228dacb5d6f18e8f222054))

## [1.0.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.1...v1.0.2) (2025-09-29)


### Bug Fixes

* **rpc_agent:** include config directory in gem package ([#128](https://github.com/ForestAdmin/agent-ruby/issues/128)) ([297ea95](https://github.com/ForestAdmin/agent-ruby/commit/297ea957f3bc8e3a25a3327cd2ea3c682e35082a))

## [1.0.1](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0...v1.0.1) (2025-09-23)

# 1.0.0 (2025-09-22)


### Bug Fixes

* load OpenIDConnect constant to prevent uninitialized error ([edf557a](https://github.com/ForestAdmin/agent-ruby/commit/edf557a8c83ebfd12a0f0d7a79ee8d10ca317533))
* load OpenIDConnect constant to prevent uninitialized error ([#116](https://github.com/ForestAdmin/agent-ruby/issues/116)) ([f7b0a5f](https://github.com/ForestAdmin/agent-ruby/commit/f7b0a5f6439ed37d85f1dfe6c6d59e120085900e))
* proper raise of OpenIDConnect Exceptions ([#112](https://github.com/ForestAdmin/agent-ruby/issues/112)) ([81370ed](https://github.com/ForestAdmin/agent-ruby/commit/81370ed5e25b8e4250de18b65e8c58afec042665))
* reorder filter and grouping operations in QueryAggregate ([#119](https://github.com/ForestAdmin/agent-ruby/issues/119)) ([65e76a1](https://github.com/ForestAdmin/agent-ruby/commit/65e76a181ae621021029dde0328183c1fe1c475a))
* replace ambiguous Error with ForestAdminAgent Error ([#117](https://github.com/ForestAdmin/agent-ruby/issues/117)) ([6529ca0](https://github.com/ForestAdmin/agent-ruby/commit/6529ca0322c8ea2f1032ebfe37ccfa406975baee))
* **active_record:** introspection should not crash on an unconventional relation ([#66](https://github.com/ForestAdmin/agent-ruby/issues/66)) ([976420a](https://github.com/ForestAdmin/agent-ruby/commit/976420a6354ce1ad9bc0770a88ac61f8907ff0d2))
* **active_record:** return default string type and add log when field type is unknown ([#95](https://github.com/ForestAdmin/agent-ruby/issues/95)) ([19db22a](https://github.com/ForestAdmin/agent-ruby/commit/19db22a30f6cc9df0f09e1ad1d532a1afb44c05a))
* **charts:** properly format week of year ([#103](https://github.com/ForestAdmin/agent-ruby/issues/103)) ([6774d27](https://github.com/ForestAdmin/agent-ruby/commit/6774d27b1352af219048599ad42bbba225c56703))
* **collection:** add missing function enable_search and add_segments ([#91](https://github.com/ForestAdmin/agent-ruby/issues/91)) ([58dc7e6](https://github.com/ForestAdmin/agent-ruby/commit/58dc7e6eeea8d529b356dbf5607e840599b55634))
* **computed:** allow to use computed decorator with nested relations ([#62](https://github.com/ForestAdmin/agent-ruby/issues/62)) ([b065d84](https://github.com/ForestAdmin/agent-ruby/commit/b065d84f20faac476f5d5a05e87f01dfcbe4d95e))
* **form:** remove type attribute from schema layout element ([#77](https://github.com/ForestAdmin/agent-ruby/issues/77)) ([19e6b45](https://github.com/ForestAdmin/agent-ruby/commit/19e6b457aa06d9ddb89f1cbb0220832ba05dfba2))
* **introspection:** ignore models that do not have primary key  ([#64](https://github.com/ForestAdmin/agent-ruby/issues/64)) ([49bbb97](https://github.com/ForestAdmin/agent-ruby/commit/49bbb979de11dfddb37692301d6bf5fda6afe09d))
* **permission:** get approval conditions by role id  ([#82](https://github.com/ForestAdmin/agent-ruby/issues/82)) ([bd4b3e7](https://github.com/ForestAdmin/agent-ruby/commit/bd4b3e7f2b978d86fb50fdcd9470162440089f64))
* **permissions:** properly check permissions when dissociating or deleting related resources ([#75](https://github.com/ForestAdmin/agent-ruby/issues/75)) ([d0239de](https://github.com/ForestAdmin/agent-ruby/commit/d0239defa2a1e00936f8c2c64723684306c8e945))
* **polymorphic:** prevent update path when not rename polymorphic relation field ([#96](https://github.com/ForestAdmin/agent-ruby/issues/96)) ([46d3251](https://github.com/ForestAdmin/agent-ruby/commit/46d32518e16efda9558f2aaea4873d7249a199d1))
* **publication:** log warning when relation field is unknown and return false ([#107](https://github.com/ForestAdmin/agent-ruby/issues/107)) ([14adf3f](https://github.com/ForestAdmin/agent-ruby/commit/14adf3fc021fcafa3736ca16aeea67b327d10fe7))
* **relation:** add support of has_and_belongs_to_many relations ([#105](https://github.com/ForestAdmin/agent-ruby/issues/105)) ([09eeca0](https://github.com/ForestAdmin/agent-ruby/commit/09eeca08accc01f46ee60e474b851cda3441665a))
* **relation:** support has_one through when through collection has 2 belongs_to ([#109](https://github.com/ForestAdmin/agent-ruby/issues/109)) ([3bf698c](https://github.com/ForestAdmin/agent-ruby/commit/3bf698cabbd8a9901216e778c71036ba81ae045c))
* **search:** mark schema as dirty when search is disable or replace search is set ([#93](https://github.com/ForestAdmin/agent-ruby/issues/93)) ([b5f4799](https://github.com/ForestAdmin/agent-ruby/commit/b5f4799c9416b40d9989eef4f6f714cbb5d4ff41))
* add safe navigation operator to get the inverse_of relation ([#97](https://github.com/ForestAdmin/agent-ruby/issues/97)) ([bc17389](https://github.com/ForestAdmin/agent-ruby/commit/bc17389282c17f0f8cf852273b58b1a558bdff17))
* allow replace_search to accept a block ([#102](https://github.com/ForestAdmin/agent-ruby/issues/102)) ([6f2d35e](https://github.com/ForestAdmin/agent-ruby/commit/6f2d35ee59f8e9a980651ec85aa660d170626574))
* ci ([0358208](https://github.com/ForestAdmin/agent-ruby/commit/0358208ae2631e9aec3874090e2ac1813d4ef60f))
* ci deploy ([2f7653d](https://github.com/ForestAdmin/agent-ruby/commit/2f7653d520485ddc747a82126de0bb78f2341443))
* ci deploy agent_ruby ([#15](https://github.com/ForestAdmin/agent-ruby/issues/15)) ([2ab162f](https://github.com/ForestAdmin/agent-ruby/commit/2ab162fff9b556433d8ad4f839fcfda0cd797e98))
* ci deploy multiple packages ([d790bab](https://github.com/ForestAdmin/agent-ruby/commit/d790babff4cd5f9762cf3c6473e710c549fe9d79))
* ci remove rubygems_mfa_required ([#14](https://github.com/ForestAdmin/agent-ruby/issues/14)) ([848cdf9](https://github.com/ForestAdmin/agent-ruby/commit/848cdf9a590981b7b67adac93f6e51d87c6440f3))
* comment out slack release ([9854f43](https://github.com/ForestAdmin/agent-ruby/commit/9854f430d46ef943c293ef1193c2c3e03a99c978))
* decorators and toolkit for work with polymorphic relations ([#67](https://github.com/ForestAdmin/agent-ruby/issues/67)) ([e95dd58](https://github.com/ForestAdmin/agent-ruby/commit/e95dd58dd6e2d936894acf0388a67e0cb71c5e32))
* display custom success/error messages for actions ([#101](https://github.com/ForestAdmin/agent-ruby/issues/101)) ([083c8e0](https://github.com/ForestAdmin/agent-ruby/commit/083c8e05799dd139744204008bd359653add52d3))
* ensure correct values are returned for user tags in context variables ([#79](https://github.com/ForestAdmin/agent-ruby/issues/79)) ([02eb548](https://github.com/ForestAdmin/agent-ruby/commit/02eb548df31c1444502340f18bd4d15ba5795ca9))
* release on forest_admin_datasource_customizer package ([#61](https://github.com/ForestAdmin/agent-ruby/issues/61)) ([10b8726](https://github.com/ForestAdmin/agent-ruby/commit/10b8726557a41d14f17a404f7a4012d7869083df))
* workflow for coverage upload to codeclimate ([#99](https://github.com/ForestAdmin/agent-ruby/issues/99)) ([ef38cd3](https://github.com/ForestAdmin/agent-ruby/commit/ef38cd3d37fb3a3ee6395a8fcfa55122c4c3c87c))
* **rename decorator:** properly map relation when renaming pk field  ([#85](https://github.com/ForestAdmin/agent-ruby/issues/85)) ([cfb2d12](https://github.com/ForestAdmin/agent-ruby/commit/cfb2d128e06b44c1533e4cbfe96128326229c8d4))
* **search:** collection is not always searchable ([#92](https://github.com/ForestAdmin/agent-ruby/issues/92)) ([96824b7](https://github.com/ForestAdmin/agent-ruby/commit/96824b7c07a6497f874f076aad80dceb599b5326))
* **security:** patch braces dependency vulnerabilities ([#56](https://github.com/ForestAdmin/agent-ruby/issues/56)) ([699446e](https://github.com/ForestAdmin/agent-ruby/commit/699446e7e7c4d42e0cb9a5b42578fdc4719a742e))
* **security:** patch cross-spawn dependency vulnerabilities ([#83](https://github.com/ForestAdmin/agent-ruby/issues/83)) ([9fd5aeb](https://github.com/ForestAdmin/agent-ruby/commit/9fd5aeb4e63f5b7542d389c99153e379499e7624))
* **security:** patch ip dependency vulnerabilities ([#28](https://github.com/ForestAdmin/agent-ruby/issues/28)) ([6988f97](https://github.com/ForestAdmin/agent-ruby/commit/6988f97f9eb549edde39277c3b9a1fbfe9364662))
* **security:** patch micromatch dependency vulnerabilities ([#68](https://github.com/ForestAdmin/agent-ruby/issues/68)) ([a0d5cf5](https://github.com/ForestAdmin/agent-ruby/commit/a0d5cf5a610e0f8316ffe9563a4cc5473522865c))
* **security:** patch micromatch dependency vulnerabilities ([#84](https://github.com/ForestAdmin/agent-ruby/issues/84)) ([fa5b38f](https://github.com/ForestAdmin/agent-ruby/commit/fa5b38fbb6fbaf9b46d14e1f1794a0dd5c1ca5bf))
* add emulate_field_filtering missing method on customizer ([#49](https://github.com/ForestAdmin/agent-ruby/issues/49)) ([41dfb0e](https://github.com/ForestAdmin/agent-ruby/commit/41dfb0eb8a27e7797057eeeed9ecd349dacda8f3))
* ci deploy packages ([9541ba0](https://github.com/ForestAdmin/agent-ruby/commit/9541ba0bb83842adfb13b43d74b1f2ad58d363ff))
* ci deploy packages to rubygems ([75b32f5](https://github.com/ForestAdmin/agent-ruby/commit/75b32f5caa82216e8fe9d50d2f00c24ce7de841c))
* ci releaserc deploy packages ([e9402a4](https://github.com/ForestAdmin/agent-ruby/commit/e9402a404a6b6021e847dbb9bed67e32e3922612))
* ci setup credentials ([5a33f54](https://github.com/ForestAdmin/agent-ruby/commit/5a33f5436611470dcce01ab9f67a23ab28029c66))
* deploy packages on rubygems ([#13](https://github.com/ForestAdmin/agent-ruby/issues/13)) ([ca07d9b](https://github.com/ForestAdmin/agent-ruby/commit/ca07d9b470da1b5fea8863b4bbfe8ffc22282836))
* gemspecs load packages from rubygems ([#60](https://github.com/ForestAdmin/agent-ruby/issues/60)) ([8c3feaf](https://github.com/ForestAdmin/agent-ruby/commit/8c3feaf70734586593208bf23c74da8d5335e465))
* polished after doc review ([#51](https://github.com/ForestAdmin/agent-ruby/issues/51)) ([055a153](https://github.com/ForestAdmin/agent-ruby/commit/055a1531d313b889fc9f2cc45755bc9555348c65))
* search behaviour  ([#55](https://github.com/ForestAdmin/agent-ruby/issues/55)) ([e429c4c](https://github.com/ForestAdmin/agent-ruby/commit/e429c4cf373a15617d12b6623da6d96283d5d582))
* unscoped active record query ([#65](https://github.com/ForestAdmin/agent-ruby/issues/65)) ([c975334](https://github.com/ForestAdmin/agent-ruby/commit/c975334d711de00878aa46f6a6266214a8084a53))
* **authentication:** return errors detail instead of generic error 500 ([#11](https://github.com/ForestAdmin/agent-ruby/issues/11)) ([19f84e5](https://github.com/ForestAdmin/agent-ruby/commit/19f84e54422ec6b0d2899621832023550e5d81a3))
* **security:** patch tar dependency vulnerabilities ([#40](https://github.com/ForestAdmin/agent-ruby/issues/40)) ([86be2a7](https://github.com/ForestAdmin/agent-ruby/commit/86be2a752011f469649cec0f09b55aa5939936d0))
* **security:** patch tar dependency vulnerabilities ([#57](https://github.com/ForestAdmin/agent-ruby/issues/57)) ([b86f396](https://github.com/ForestAdmin/agent-ruby/commit/b86f396d278902aba1ad1f569229dcb22e4ac2ef))
* rubocop lint ([#38](https://github.com/ForestAdmin/agent-ruby/issues/38)) ([48b658f](https://github.com/ForestAdmin/agent-ruby/commit/48b658f02949a29ed9a8f35beaa5d83ced6a8dfb))


### Features

*  add customizer with decorator stack and empty-decorator ([#18](https://github.com/ForestAdmin/agent-ruby/issues/18)) ([900effd](https://github.com/ForestAdmin/agent-ruby/commit/900effd6f30218a7411e6858e13d72331cee6c15))
*  add write decorator support ([#36](https://github.com/ForestAdmin/agent-ruby/issues/36)) ([f052601](https://github.com/ForestAdmin/agent-ruby/commit/f0526015db0ddc83aa3ddf972628790fd0825575))
* add all writing operations ([#9](https://github.com/ForestAdmin/agent-ruby/issues/9)) ([3fd6a7a](https://github.com/ForestAdmin/agent-ruby/commit/3fd6a7a9d1dbe21e8689f2d54ae9b9abf13c17a5))
* add authentication  ([#3](https://github.com/ForestAdmin/agent-ruby/issues/3)) ([ce369fd](https://github.com/ForestAdmin/agent-ruby/commit/ce369fd8999d048150d733332d5806d8678e7a14))
* add binary decorator support ([#42](https://github.com/ForestAdmin/agent-ruby/issues/42)) ([0e03047](https://github.com/ForestAdmin/agent-ruby/commit/0e0304753337fb8034ed2250d2c3d0a7b537b52e))
* add chart decorator support ([#37](https://github.com/ForestAdmin/agent-ruby/issues/37)) ([c1fc0ac](https://github.com/ForestAdmin/agent-ruby/commit/c1fc0acb6109c396e500bf202d0e8eb20bc28943))
* add charts support ([#16](https://github.com/ForestAdmin/agent-ruby/issues/16)) ([a8d609f](https://github.com/ForestAdmin/agent-ruby/commit/a8d609fb4e1e963722debb7e36bd2f9f3e6c42de))
* add export routes support ([#50](https://github.com/ForestAdmin/agent-ruby/issues/50)) ([1377185](https://github.com/ForestAdmin/agent-ruby/commit/137718585056b38bfa29735e8075c13ab40c6230))
* add export_limit_size support for csv ([#123](https://github.com/ForestAdmin/agent-ruby/issues/123)) ([8712d35](https://github.com/ForestAdmin/agent-ruby/commit/8712d35bf99b7c77cbb662f5f95dae4b253fb60d))
* add forestadmin schema generate ([#4](https://github.com/ForestAdmin/agent-ruby/issues/4)) ([329397b](https://github.com/ForestAdmin/agent-ruby/commit/329397b4218373037d031607c763d81fe3126465))
* add hook decorator support ([#39](https://github.com/ForestAdmin/agent-ruby/issues/39)) ([1514aed](https://github.com/ForestAdmin/agent-ruby/commit/1514aed9a615fce2385fceea9099852e06f9e301))
* add ipwhitelist support ([#7](https://github.com/ForestAdmin/agent-ruby/issues/7)) ([680a17d](https://github.com/ForestAdmin/agent-ruby/commit/680a17dd8642d345444ef39d32285847c7992043))
* add jsonapi serializer ([#5](https://github.com/ForestAdmin/agent-ruby/issues/5)) ([3528191](https://github.com/ForestAdmin/agent-ruby/commit/35281919260084dbe20b32e2e3cd7f5ee1cdc54b))
* add lazy join decorator to improve performance ([#89](https://github.com/ForestAdmin/agent-ruby/issues/89)) ([3a17fd1](https://github.com/ForestAdmin/agent-ruby/commit/3a17fd160eae5a340660588c32f55823312036d2))
* add list and count api ([#6](https://github.com/ForestAdmin/agent-ruby/issues/6)) ([19b5bd9](https://github.com/ForestAdmin/agent-ruby/commit/19b5bd9ebb121f4c40e11f340d914dee4a84dc68))
* add logs in dev mode ([#43](https://github.com/ForestAdmin/agent-ruby/issues/43)) ([da941af](https://github.com/ForestAdmin/agent-ruby/commit/da941af365b1ca48832eaa32c7cf29880a5a66b7))
* add mongoid datasource ([#111](https://github.com/ForestAdmin/agent-ruby/issues/111)) ([b9b90cc](https://github.com/ForestAdmin/agent-ruby/commit/b9b90cc5041a5867cfa08a2a7eaa7113fb9b8618))
* add native driver support ([#54](https://github.com/ForestAdmin/agent-ruby/issues/54)) ([aea9c32](https://github.com/ForestAdmin/agent-ruby/commit/aea9c3257538ec52c4acfd95ff443084e5daf385))
* add operator emulate support ([#31](https://github.com/ForestAdmin/agent-ruby/issues/31)) ([fc6c7b5](https://github.com/ForestAdmin/agent-ruby/commit/fc6c7b5f3f31374936e89f84f69330433263904e))
* add override decorator support ([#46](https://github.com/ForestAdmin/agent-ruby/issues/46)) ([a581678](https://github.com/ForestAdmin/agent-ruby/commit/a581678d487b7129c61b884d10bd8631a987a113))
* add package to provide test tools  ([#88](https://github.com/ForestAdmin/agent-ruby/issues/88)) ([6e15882](https://github.com/ForestAdmin/agent-ruby/commit/6e15882e3dd8e8976d2de5de176c0c07d4faee46))
* add pages in action forms ([#74](https://github.com/ForestAdmin/agent-ruby/issues/74)) ([2a8a7f4](https://github.com/ForestAdmin/agent-ruby/commit/2a8a7f43104bc584e1ae35d433af4b146267eb08))
* add permissions support ([#17](https://github.com/ForestAdmin/agent-ruby/issues/17)) ([d7b14ca](https://github.com/ForestAdmin/agent-ruby/commit/d7b14ca8a32a049b8aabf47b0cbf1b165f3b7ad0))
* add polymorphic support ([#63](https://github.com/ForestAdmin/agent-ruby/issues/63)) ([80566a5](https://github.com/ForestAdmin/agent-ruby/commit/80566a5bb5083a5139426299b8d86dea33686421))
* add publication decorator support ([#34](https://github.com/ForestAdmin/agent-ruby/issues/34)) ([7550e10](https://github.com/ForestAdmin/agent-ruby/commit/7550e10a50e99934776522e8650523413202f9b0))
* add related routes ([#12](https://github.com/ForestAdmin/agent-ruby/issues/12)) ([78e5a04](https://github.com/ForestAdmin/agent-ruby/commit/78e5a0404a1e11f4ee16a9e69226c4b1c0028759))
* add relation decorator support  ([#29](https://github.com/ForestAdmin/agent-ruby/issues/29)) ([e181b5f](https://github.com/ForestAdmin/agent-ruby/commit/e181b5f82fb8a8b1fbf835545daa0145a219cea1))
* add rename collection decorator support ([#35](https://github.com/ForestAdmin/agent-ruby/issues/35)) ([e0cad85](https://github.com/ForestAdmin/agent-ruby/commit/e0cad85b00e9b9335c8ff9c4bc062b77408bd42e))
* add rename field decorator support ([#33](https://github.com/ForestAdmin/agent-ruby/issues/33)) ([1bcfd42](https://github.com/ForestAdmin/agent-ruby/commit/1bcfd4294cc0df1e0cca29f7419e30dcc82d9d75))
* add request ip to user context ([#80](https://github.com/ForestAdmin/agent-ruby/issues/80)) ([08e4276](https://github.com/ForestAdmin/agent-ruby/commit/08e4276b1b16ae0bb98257224652d3164b3d6bb1))
* add RPC datasource support ([#114](https://github.com/ForestAdmin/agent-ruby/issues/114)) ([b87bd75](https://github.com/ForestAdmin/agent-ruby/commit/b87bd75bfa8832e4bbe8d253a287faa4f544e27a))
* add schema decorator support ([#19](https://github.com/ForestAdmin/agent-ruby/issues/19)) ([3548290](https://github.com/ForestAdmin/agent-ruby/commit/354829022257d11aeb106ad760360adfe22bceff))
* add scope invalidation endpoint ([#58](https://github.com/ForestAdmin/agent-ruby/issues/58)) ([36a3aa7](https://github.com/ForestAdmin/agent-ruby/commit/36a3aa7e7ad890e68fcf6368b936149bb1645fae))
* add segment decorator support ([#41](https://github.com/ForestAdmin/agent-ruby/issues/41)) ([3b4e437](https://github.com/ForestAdmin/agent-ruby/commit/3b4e437460d7ac7d0c2eda291ddde241cff0fce9))
* add sorting of models and fields in apimap ([#121](https://github.com/ForestAdmin/agent-ruby/issues/121)) ([18b63e0](https://github.com/ForestAdmin/agent-ruby/commit/18b63e0b6b0e192350651e9c0aa6db31ca6ca051))
* better error response formatting and logging ([#118](https://github.com/ForestAdmin/agent-ruby/issues/118)) ([31c7a57](https://github.com/ForestAdmin/agent-ruby/commit/31c7a577e115ce6f96330d4e34c578ace5c982ad))
* improve error handling ([#120](https://github.com/ForestAdmin/agent-ruby/issues/120)) ([7952e95](https://github.com/ForestAdmin/agent-ruby/commit/7952e957041ca76652c6888db66a796734f49431))
* **action:** add action widgets support ([#53](https://github.com/ForestAdmin/agent-ruby/issues/53)) ([51605b2](https://github.com/ForestAdmin/agent-ruby/commit/51605b2b1136a4a9f44b5f442803415f717bbae9))
* **action:** add permission on action routes ([#27](https://github.com/ForestAdmin/agent-ruby/issues/27)) ([c7361f7](https://github.com/ForestAdmin/agent-ruby/commit/c7361f753c40a8b4abfc4245aeb17f244c7fec02))
* **action_form:** add row layout customization ([#71](https://github.com/ForestAdmin/agent-ruby/issues/71)) ([1dea61a](https://github.com/ForestAdmin/agent-ruby/commit/1dea61abbf7ed61f956b1f6e3a173df7daa37b55))
* **caller:** add project and environment ([#81](https://github.com/ForestAdmin/agent-ruby/issues/81)) ([59a98fa](https://github.com/ForestAdmin/agent-ruby/commit/59a98fa766dafc172cd6eed9b952b75acb918015))
* **capabilities:** add native query support ([#86](https://github.com/ForestAdmin/agent-ruby/issues/86)) ([88213ae](https://github.com/ForestAdmin/agent-ruby/commit/88213ae41a0c43fd82b1bf815fc0806ff568ce4e))
* **capabilities:** add new collections route ([#78](https://github.com/ForestAdmin/agent-ruby/issues/78)) ([d868174](https://github.com/ForestAdmin/agent-ruby/commit/d8681746c83bada9f198b99951e6ee797e9f8ea0))
* **decorator:** add action support ([#24](https://github.com/ForestAdmin/agent-ruby/issues/24)) ([e586476](https://github.com/ForestAdmin/agent-ruby/commit/e586476589c8f81fb741c5d11bd1f931c1d4e439))
* **decorator:** add operators equivalence support  ([#20](https://github.com/ForestAdmin/agent-ruby/issues/20)) ([006c49a](https://github.com/ForestAdmin/agent-ruby/commit/006c49a1f1ac4c936b7a0ab9555ae81a884a0e5d))
* **decorator:** add search support ([#21](https://github.com/ForestAdmin/agent-ruby/issues/21)) ([a71acc6](https://github.com/ForestAdmin/agent-ruby/commit/a71acc6391fe14d38fc7204c8942de4c95fcbd1f))
* **engine:** improve setup agent ([#8](https://github.com/ForestAdmin/agent-ruby/issues/8)) ([8fb5c29](https://github.com/ForestAdmin/agent-ruby/commit/8fb5c29b3cb611f6847985c099d6a9bd33e442b3))
* **form:** add description and submit button customization ([#72](https://github.com/ForestAdmin/agent-ruby/issues/72)) ([a42ce7a](https://github.com/ForestAdmin/agent-ruby/commit/a42ce7a19545e15905fe836485a11ad97bd07bf3))
* **form:** add HtmlBlock layout element ([#70](https://github.com/ForestAdmin/agent-ruby/issues/70)) ([0ba5669](https://github.com/ForestAdmin/agent-ruby/commit/0ba5669b8ec94348d33b8981c07bbe244369a9b9))
* **form:** add id in form fields ([#73](https://github.com/ForestAdmin/agent-ruby/issues/73)) ([363d700](https://github.com/ForestAdmin/agent-ruby/commit/363d7003b6433255c46c7c00731ef6246b728de2))
* **form:** add separator layout element ([#69](https://github.com/ForestAdmin/agent-ruby/issues/69)) ([5bfbd7a](https://github.com/ForestAdmin/agent-ruby/commit/5bfbd7a0508486a968f959c2650e758624b18964))
* **form:** add support of static form with layout elements ([#76](https://github.com/ForestAdmin/agent-ruby/issues/76)) ([ecf5f1a](https://github.com/ForestAdmin/agent-ruby/commit/ecf5f1a105e38d5fe5f7df4fd970093373627938))
* expose plugin to datasource-customizer ([#52](https://github.com/ForestAdmin/agent-ruby/issues/52)) ([2d36337](https://github.com/ForestAdmin/agent-ruby/commit/2d36337d3f93df261f9ccc2c7db8df183d4d92f0))
* **plugin:** add new import field plugin ([#47](https://github.com/ForestAdmin/agent-ruby/issues/47)) ([be7b575](https://github.com/ForestAdmin/agent-ruby/commit/be7b575147fabc6c833a7339d2444be64e24e75f))
* add sort decorator support ([#32](https://github.com/ForestAdmin/agent-ruby/issues/32)) ([a5320fc](https://github.com/ForestAdmin/agent-ruby/commit/a5320fca5a6b30d49ad1471fd9068ac7d65ed3e1))
* add validation support ([#30](https://github.com/ForestAdmin/agent-ruby/issues/30)) ([a0e8092](https://github.com/ForestAdmin/agent-ruby/commit/a0e80923ad1b75286d911ed96ef5e6baef0b022a))
* added filters feature ([#10](https://github.com/ForestAdmin/agent-ruby/issues/10)) ([9210563](https://github.com/ForestAdmin/agent-ruby/commit/92105633205c61679749f805bff23da6c88dd912))
* support multi field sorting from frontend ([#44](https://github.com/ForestAdmin/agent-ruby/issues/44)) ([eadde5d](https://github.com/ForestAdmin/agent-ruby/commit/eadde5d9d53ca56bbaf3f139780041e114f7c8a6))
* **decorator:** add compute support ([#23](https://github.com/ForestAdmin/agent-ruby/issues/23)) ([3345fb4](https://github.com/ForestAdmin/agent-ruby/commit/3345fb483c94296614a0f90251adba4845f1e90c))
* **serializer:** serialize hash instead of an active record object ([#22](https://github.com/ForestAdmin/agent-ruby/issues/22)) ([70dea37](https://github.com/ForestAdmin/agent-ruby/commit/70dea37982c201c3a547638f7b21cd0500b37014))

# [1.0.0-beta.110](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.109...v1.0.0-beta.110) (2025-09-22)


### Features

* add export_limit_size support for csv ([#123](https://github.com/ForestAdmin/agent-ruby/issues/123)) ([8712d35](https://github.com/ForestAdmin/agent-ruby/commit/8712d35bf99b7c77cbb662f5f95dae4b253fb60d))

# [1.0.0-beta.109](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.108...v1.0.0-beta.109) (2025-09-17)


### Features

* add sorting of models and fields in apimap ([#121](https://github.com/ForestAdmin/agent-ruby/issues/121)) ([18b63e0](https://github.com/ForestAdmin/agent-ruby/commit/18b63e0b6b0e192350651e9c0aa6db31ca6ca051))

# [1.0.0-beta.108](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.107...v1.0.0-beta.108) (2025-09-11)


### Features

* improve error handling ([#120](https://github.com/ForestAdmin/agent-ruby/issues/120)) ([7952e95](https://github.com/ForestAdmin/agent-ruby/commit/7952e957041ca76652c6888db66a796734f49431))

# [1.0.0-beta.107](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.106...v1.0.0-beta.107) (2025-07-01)


### Bug Fixes

* reorder filter and grouping operations in QueryAggregate ([#119](https://github.com/ForestAdmin/agent-ruby/issues/119)) ([65e76a1](https://github.com/ForestAdmin/agent-ruby/commit/65e76a181ae621021029dde0328183c1fe1c475a))

# [1.0.0-beta.106](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.105...v1.0.0-beta.106) (2025-06-12)


### Features

* better error response formatting and logging ([#118](https://github.com/ForestAdmin/agent-ruby/issues/118)) ([31c7a57](https://github.com/ForestAdmin/agent-ruby/commit/31c7a577e115ce6f96330d4e34c578ace5c982ad))

# [1.0.0-beta.105](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.104...v1.0.0-beta.105) (2025-06-11)


### Bug Fixes

* replace ambiguous Error with ForestAdminAgent Error ([#117](https://github.com/ForestAdmin/agent-ruby/issues/117)) ([6529ca0](https://github.com/ForestAdmin/agent-ruby/commit/6529ca0322c8ea2f1032ebfe37ccfa406975baee))

# [1.0.0-beta.104](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.103...v1.0.0-beta.104) (2025-06-11)


### Bug Fixes

* load OpenIDConnect constant to prevent uninitialized error ([#116](https://github.com/ForestAdmin/agent-ruby/issues/116)) ([f7b0a5f](https://github.com/ForestAdmin/agent-ruby/commit/f7b0a5f6439ed37d85f1dfe6c6d59e120085900e))

# [1.0.0-beta.103](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.102...v1.0.0-beta.103) (2025-06-11)


### Bug Fixes

* load OpenIDConnect constant to prevent uninitialized error ([edf557a](https://github.com/ForestAdmin/agent-ruby/commit/edf557a8c83ebfd12a0f0d7a79ee8d10ca317533))

# [1.0.0-beta.102](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.101...v1.0.0-beta.102) (2025-05-27)


### Features

* add RPC datasource support ([#114](https://github.com/ForestAdmin/agent-ruby/issues/114)) ([b87bd75](https://github.com/ForestAdmin/agent-ruby/commit/b87bd75bfa8832e4bbe8d253a287faa4f544e27a))

# [1.0.0-beta.101](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.100...v1.0.0-beta.101) (2025-05-21)


### Bug Fixes

* **search:** mark schema as dirty when search is disable or replace search is set ([#93](https://github.com/ForestAdmin/agent-ruby/issues/93)) ([b5f4799](https://github.com/ForestAdmin/agent-ruby/commit/b5f4799c9416b40d9989eef4f6f714cbb5d4ff41))

# [1.0.0-beta.100](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.99...v1.0.0-beta.100) (2025-03-10)


### Features

* add mongoid datasource ([#111](https://github.com/ForestAdmin/agent-ruby/issues/111)) ([b9b90cc](https://github.com/ForestAdmin/agent-ruby/commit/b9b90cc5041a5867cfa08a2a7eaa7113fb9b8618))

# [1.0.0-beta.99](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.98...v1.0.0-beta.99) (2025-02-27)


### Bug Fixes

* proper raise of OpenIDConnect Exceptions ([#112](https://github.com/ForestAdmin/agent-ruby/issues/112)) ([81370ed](https://github.com/ForestAdmin/agent-ruby/commit/81370ed5e25b8e4250de18b65e8c58afec042665))

# [1.0.0-beta.98](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.97...v1.0.0-beta.98) (2025-02-25)


### Bug Fixes

* **relation:** support has_one through when through collection has 2 belongs_to ([#109](https://github.com/ForestAdmin/agent-ruby/issues/109)) ([3bf698c](https://github.com/ForestAdmin/agent-ruby/commit/3bf698cabbd8a9901216e778c71036ba81ae045c))

# [1.0.0-beta.97](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.96...v1.0.0-beta.97) (2025-02-24)


### Bug Fixes

* **publication:** log warning when relation field is unknown and return false ([#107](https://github.com/ForestAdmin/agent-ruby/issues/107)) ([14adf3f](https://github.com/ForestAdmin/agent-ruby/commit/14adf3fc021fcafa3736ca16aeea67b327d10fe7))

# [1.0.0-beta.96](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.95...v1.0.0-beta.96) (2025-02-20)


### Bug Fixes

* **charts:** properly format week of year ([#103](https://github.com/ForestAdmin/agent-ruby/issues/103)) ([6774d27](https://github.com/ForestAdmin/agent-ruby/commit/6774d27b1352af219048599ad42bbba225c56703))
* **relation:** add support of has_and_belongs_to_many relations ([#105](https://github.com/ForestAdmin/agent-ruby/issues/105)) ([09eeca0](https://github.com/ForestAdmin/agent-ruby/commit/09eeca08accc01f46ee60e474b851cda3441665a))

# [1.0.0-beta.95](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.94...v1.0.0-beta.95) (2025-01-30)


### Bug Fixes

* allow replace_search to accept a block ([#102](https://github.com/ForestAdmin/agent-ruby/issues/102)) ([6f2d35e](https://github.com/ForestAdmin/agent-ruby/commit/6f2d35ee59f8e9a980651ec85aa660d170626574))

# [1.0.0-beta.94](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.93...v1.0.0-beta.94) (2025-01-28)


### Bug Fixes

* display custom success/error messages for actions ([#101](https://github.com/ForestAdmin/agent-ruby/issues/101)) ([083c8e0](https://github.com/ForestAdmin/agent-ruby/commit/083c8e05799dd139744204008bd359653add52d3))

# [1.0.0-beta.93](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.92...v1.0.0-beta.93) (2025-01-27)


### Bug Fixes

* add safe navigation operator to get the inverse_of relation ([#97](https://github.com/ForestAdmin/agent-ruby/issues/97)) ([bc17389](https://github.com/ForestAdmin/agent-ruby/commit/bc17389282c17f0f8cf852273b58b1a558bdff17))

# [1.0.0-beta.92](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.91...v1.0.0-beta.92) (2025-01-27)


### Bug Fixes

* workflow for coverage upload to codeclimate ([#99](https://github.com/ForestAdmin/agent-ruby/issues/99)) ([ef38cd3](https://github.com/ForestAdmin/agent-ruby/commit/ef38cd3d37fb3a3ee6395a8fcfa55122c4c3c87c))

# [1.0.0-beta.91](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.90...v1.0.0-beta.91) (2025-01-20)


### Bug Fixes

* **polymorphic:** prevent update path when not rename polymorphic relation field ([#96](https://github.com/ForestAdmin/agent-ruby/issues/96)) ([46d3251](https://github.com/ForestAdmin/agent-ruby/commit/46d32518e16efda9558f2aaea4873d7249a199d1))

# [1.0.0-beta.90](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.89...v1.0.0-beta.90) (2025-01-15)


### Bug Fixes

* **active_record:** return default string type and add log when field type is unknown ([#95](https://github.com/ForestAdmin/agent-ruby/issues/95)) ([19db22a](https://github.com/ForestAdmin/agent-ruby/commit/19db22a30f6cc9df0f09e1ad1d532a1afb44c05a))

# [1.0.0-beta.89](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.88...v1.0.0-beta.89) (2025-01-08)


### Features

* **caller:** add project and environment ([#81](https://github.com/ForestAdmin/agent-ruby/issues/81)) ([59a98fa](https://github.com/ForestAdmin/agent-ruby/commit/59a98fa766dafc172cd6eed9b952b75acb918015))

# [1.0.0-beta.88](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.87...v1.0.0-beta.88) (2025-01-08)


### Features

* add lazy join decorator to improve performance ([#89](https://github.com/ForestAdmin/agent-ruby/issues/89)) ([3a17fd1](https://github.com/ForestAdmin/agent-ruby/commit/3a17fd160eae5a340660588c32f55823312036d2))

# [1.0.0-beta.87](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.86...v1.0.0-beta.87) (2025-01-06)


### Bug Fixes

* **search:** collection is not always searchable ([#92](https://github.com/ForestAdmin/agent-ruby/issues/92)) ([96824b7](https://github.com/ForestAdmin/agent-ruby/commit/96824b7c07a6497f874f076aad80dceb599b5326))

# [1.0.0-beta.86](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.85...v1.0.0-beta.86) (2025-01-06)


### Bug Fixes

* **collection:** add missing function enable_search and add_segments ([#91](https://github.com/ForestAdmin/agent-ruby/issues/91)) ([58dc7e6](https://github.com/ForestAdmin/agent-ruby/commit/58dc7e6eeea8d529b356dbf5607e840599b55634))

# [1.0.0-beta.85](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.84...v1.0.0-beta.85) (2024-12-19)

# [1.0.0-beta.84](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.83...v1.0.0-beta.84) (2024-12-19)


### Features

* **capabilities:** add native query support ([#86](https://github.com/ForestAdmin/agent-ruby/issues/86)) ([88213ae](https://github.com/ForestAdmin/agent-ruby/commit/88213ae41a0c43fd82b1bf815fc0806ff568ce4e))

# [1.0.0-beta.83](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.82...v1.0.0-beta.83) (2024-12-13)


### Features

* add package to provide test tools  ([#88](https://github.com/ForestAdmin/agent-ruby/issues/88)) ([6e15882](https://github.com/ForestAdmin/agent-ruby/commit/6e15882e3dd8e8976d2de5de176c0c07d4faee46))

# [1.0.0-beta.82](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.81...v1.0.0-beta.82) (2024-12-04)


### Bug Fixes

* **rename decorator:** properly map relation when renaming pk field  ([#85](https://github.com/ForestAdmin/agent-ruby/issues/85)) ([cfb2d12](https://github.com/ForestAdmin/agent-ruby/commit/cfb2d128e06b44c1533e4cbfe96128326229c8d4))

# [1.0.0-beta.81](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.80...v1.0.0-beta.81) (2024-11-22)


### Bug Fixes

* **security:** patch micromatch dependency vulnerabilities ([#84](https://github.com/ForestAdmin/agent-ruby/issues/84)) ([fa5b38f](https://github.com/ForestAdmin/agent-ruby/commit/fa5b38fbb6fbaf9b46d14e1f1794a0dd5c1ca5bf))

# [1.0.0-beta.80](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.79...v1.0.0-beta.80) (2024-11-22)


### Bug Fixes

* **security:** patch cross-spawn dependency vulnerabilities ([#83](https://github.com/ForestAdmin/agent-ruby/issues/83)) ([9fd5aeb](https://github.com/ForestAdmin/agent-ruby/commit/9fd5aeb4e63f5b7542d389c99153e379499e7624))

# [1.0.0-beta.79](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.78...v1.0.0-beta.79) (2024-11-18)


### Bug Fixes

* **permission:** get approval conditions by role id  ([#82](https://github.com/ForestAdmin/agent-ruby/issues/82)) ([bd4b3e7](https://github.com/ForestAdmin/agent-ruby/commit/bd4b3e7f2b978d86fb50fdcd9470162440089f64))

# [1.0.0-beta.78](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.77...v1.0.0-beta.78) (2024-10-28)


### Features

* add request ip to user context ([#80](https://github.com/ForestAdmin/agent-ruby/issues/80)) ([08e4276](https://github.com/ForestAdmin/agent-ruby/commit/08e4276b1b16ae0bb98257224652d3164b3d6bb1))

# [1.0.0-beta.77](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.76...v1.0.0-beta.77) (2024-10-28)


### Bug Fixes

* ensure correct values are returned for user tags in context variables ([#79](https://github.com/ForestAdmin/agent-ruby/issues/79)) ([02eb548](https://github.com/ForestAdmin/agent-ruby/commit/02eb548df31c1444502340f18bd4d15ba5795ca9))

# [1.0.0-beta.76](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.75...v1.0.0-beta.76) (2024-10-28)


### Features

* **capabilities:** add new collections route ([#78](https://github.com/ForestAdmin/agent-ruby/issues/78)) ([d868174](https://github.com/ForestAdmin/agent-ruby/commit/d8681746c83bada9f198b99951e6ee797e9f8ea0))

# [1.0.0-beta.75](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.74...v1.0.0-beta.75) (2024-10-10)


### Bug Fixes

* **permissions:** properly check permissions when dissociating or deleting related resources ([#75](https://github.com/ForestAdmin/agent-ruby/issues/75)) ([d0239de](https://github.com/ForestAdmin/agent-ruby/commit/d0239defa2a1e00936f8c2c64723684306c8e945))

# [1.0.0-beta.74](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.73...v1.0.0-beta.74) (2024-10-10)


### Bug Fixes

* **form:** remove type attribute from schema layout element ([#77](https://github.com/ForestAdmin/agent-ruby/issues/77)) ([19e6b45](https://github.com/ForestAdmin/agent-ruby/commit/19e6b457aa06d9ddb89f1cbb0220832ba05dfba2))

# [1.0.0-beta.73](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.72...v1.0.0-beta.73) (2024-10-10)


### Features

* **form:** add support of static form with layout elements ([#76](https://github.com/ForestAdmin/agent-ruby/issues/76)) ([ecf5f1a](https://github.com/ForestAdmin/agent-ruby/commit/ecf5f1a105e38d5fe5f7df4fd970093373627938))

# [1.0.0-beta.72](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.71...v1.0.0-beta.72) (2024-10-09)


### Features

* add pages in action forms ([#74](https://github.com/ForestAdmin/agent-ruby/issues/74)) ([2a8a7f4](https://github.com/ForestAdmin/agent-ruby/commit/2a8a7f43104bc584e1ae35d433af4b146267eb08))

# [1.0.0-beta.71](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.70...v1.0.0-beta.71) (2024-10-04)


### Features

* **form:** add description and submit button customization ([#72](https://github.com/ForestAdmin/agent-ruby/issues/72)) ([a42ce7a](https://github.com/ForestAdmin/agent-ruby/commit/a42ce7a19545e15905fe836485a11ad97bd07bf3))

# [1.0.0-beta.70](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.69...v1.0.0-beta.70) (2024-09-27)


### Features

* **form:** add id in form fields ([#73](https://github.com/ForestAdmin/agent-ruby/issues/73)) ([363d700](https://github.com/ForestAdmin/agent-ruby/commit/363d7003b6433255c46c7c00731ef6246b728de2))

# [1.0.0-beta.69](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.68...v1.0.0-beta.69) (2024-09-25)


### Features

* **action_form:** add row layout customization ([#71](https://github.com/ForestAdmin/agent-ruby/issues/71)) ([1dea61a](https://github.com/ForestAdmin/agent-ruby/commit/1dea61abbf7ed61f956b1f6e3a173df7daa37b55))

# [1.0.0-beta.68](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.67...v1.0.0-beta.68) (2024-09-23)


### Features

* **form:** add HtmlBlock layout element ([#70](https://github.com/ForestAdmin/agent-ruby/issues/70)) ([0ba5669](https://github.com/ForestAdmin/agent-ruby/commit/0ba5669b8ec94348d33b8981c07bbe244369a9b9))

# [1.0.0-beta.67](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.66...v1.0.0-beta.67) (2024-09-19)


### Features

* **form:** add separator layout element ([#69](https://github.com/ForestAdmin/agent-ruby/issues/69)) ([5bfbd7a](https://github.com/ForestAdmin/agent-ruby/commit/5bfbd7a0508486a968f959c2650e758624b18964))

# [1.0.0-beta.66](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.65...v1.0.0-beta.66) (2024-09-05)


### Bug Fixes

* **security:** patch micromatch dependency vulnerabilities ([#68](https://github.com/ForestAdmin/agent-ruby/issues/68)) ([a0d5cf5](https://github.com/ForestAdmin/agent-ruby/commit/a0d5cf5a610e0f8316ffe9563a4cc5473522865c))

# [1.0.0-beta.65](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.64...v1.0.0-beta.65) (2024-08-23)


### Bug Fixes

* decorators and toolkit for work with polymorphic relations ([#67](https://github.com/ForestAdmin/agent-ruby/issues/67)) ([e95dd58](https://github.com/ForestAdmin/agent-ruby/commit/e95dd58dd6e2d936894acf0388a67e0cb71c5e32))

# [1.0.0-beta.64](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.63...v1.0.0-beta.64) (2024-08-21)


### Bug Fixes

* **active_record:** introspection should not crash on an unconventional relation ([#66](https://github.com/ForestAdmin/agent-ruby/issues/66)) ([976420a](https://github.com/ForestAdmin/agent-ruby/commit/976420a6354ce1ad9bc0770a88ac61f8907ff0d2))

# [1.0.0-beta.63](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.62...v1.0.0-beta.63) (2024-08-20)


### Bug Fixes

* unscoped active record query ([#65](https://github.com/ForestAdmin/agent-ruby/issues/65)) ([c975334](https://github.com/ForestAdmin/agent-ruby/commit/c975334d711de00878aa46f6a6266214a8084a53))

# [1.0.0-beta.62](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.61...v1.0.0-beta.62) (2024-08-19)


### Features

* add polymorphic support ([#63](https://github.com/ForestAdmin/agent-ruby/issues/63)) ([80566a5](https://github.com/ForestAdmin/agent-ruby/commit/80566a5bb5083a5139426299b8d86dea33686421))

# [1.0.0-beta.61](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.60...v1.0.0-beta.61) (2024-07-26)


### Bug Fixes

* **introspection:** ignore models that do not have primary key  ([#64](https://github.com/ForestAdmin/agent-ruby/issues/64)) ([49bbb97](https://github.com/ForestAdmin/agent-ruby/commit/49bbb979de11dfddb37692301d6bf5fda6afe09d))

# [1.0.0-beta.60](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.59...v1.0.0-beta.60) (2024-07-08)


### Bug Fixes

* **computed:** allow to use computed decorator with nested relations ([#62](https://github.com/ForestAdmin/agent-ruby/issues/62)) ([b065d84](https://github.com/ForestAdmin/agent-ruby/commit/b065d84f20faac476f5d5a05e87f01dfcbe4d95e))

# [1.0.0-beta.59](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.58...v1.0.0-beta.59) (2024-07-01)


### Features

* add scope invalidation endpoint ([#58](https://github.com/ForestAdmin/agent-ruby/issues/58)) ([36a3aa7](https://github.com/ForestAdmin/agent-ruby/commit/36a3aa7e7ad890e68fcf6368b936149bb1645fae))

# [1.0.0-beta.58](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.57...v1.0.0-beta.58) (2024-06-25)


### Bug Fixes

* gemspecs load packages from rubygems ([#60](https://github.com/ForestAdmin/agent-ruby/issues/60)) ([8c3feaf](https://github.com/ForestAdmin/agent-ruby/commit/8c3feaf70734586593208bf23c74da8d5335e465))

# [1.0.0-beta.57](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.56...v1.0.0-beta.57) (2024-06-25)


### Bug Fixes

* release on forest_admin_datasource_customizer package ([#61](https://github.com/ForestAdmin/agent-ruby/issues/61)) ([10b8726](https://github.com/ForestAdmin/agent-ruby/commit/10b8726557a41d14f17a404f7a4012d7869083df))

# [1.0.0-beta.56](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.55...v1.0.0-beta.56) (2024-06-20)


### Bug Fixes

* **security:** patch braces dependency vulnerabilities ([#56](https://github.com/ForestAdmin/agent-ruby/issues/56)) ([699446e](https://github.com/ForestAdmin/agent-ruby/commit/699446e7e7c4d42e0cb9a5b42578fdc4719a742e))
* **security:** patch tar dependency vulnerabilities ([#57](https://github.com/ForestAdmin/agent-ruby/issues/57)) ([b86f396](https://github.com/ForestAdmin/agent-ruby/commit/b86f396d278902aba1ad1f569229dcb22e4ac2ef))

# [1.0.0-beta.55](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.54...v1.0.0-beta.55) (2024-06-17)


### Bug Fixes

* search behaviour  ([#55](https://github.com/ForestAdmin/agent-ruby/issues/55)) ([e429c4c](https://github.com/ForestAdmin/agent-ruby/commit/e429c4cf373a15617d12b6623da6d96283d5d582))

# [1.0.0-beta.54](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.53...v1.0.0-beta.54) (2024-06-10)


### Features

* expose plugin to datasource-customizer ([#52](https://github.com/ForestAdmin/agent-ruby/issues/52)) ([2d36337](https://github.com/ForestAdmin/agent-ruby/commit/2d36337d3f93df261f9ccc2c7db8df183d4d92f0))

# [1.0.0-beta.53](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.52...v1.0.0-beta.53) (2024-06-10)


### Features

* add native driver support ([#54](https://github.com/ForestAdmin/agent-ruby/issues/54)) ([aea9c32](https://github.com/ForestAdmin/agent-ruby/commit/aea9c3257538ec52c4acfd95ff443084e5daf385))

# [1.0.0-beta.52](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.51...v1.0.0-beta.52) (2024-06-07)


### Features

* **action:** add action widgets support ([#53](https://github.com/ForestAdmin/agent-ruby/issues/53)) ([51605b2](https://github.com/ForestAdmin/agent-ruby/commit/51605b2b1136a4a9f44b5f442803415f717bbae9))

# [1.0.0-beta.51](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.50...v1.0.0-beta.51) (2024-05-23)


### Features

* add override decorator support ([#46](https://github.com/ForestAdmin/agent-ruby/issues/46)) ([a581678](https://github.com/ForestAdmin/agent-ruby/commit/a581678d487b7129c61b884d10bd8631a987a113))

# [1.0.0-beta.50](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.49...v1.0.0-beta.50) (2024-05-23)


### Features

* **plugin:** add new import field plugin ([#47](https://github.com/ForestAdmin/agent-ruby/issues/47)) ([be7b575](https://github.com/ForestAdmin/agent-ruby/commit/be7b575147fabc6c833a7339d2444be64e24e75f))

# [1.0.0-beta.49](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.48...v1.0.0-beta.49) (2024-05-23)


### Bug Fixes

* polished after doc review ([#51](https://github.com/ForestAdmin/agent-ruby/issues/51)) ([055a153](https://github.com/ForestAdmin/agent-ruby/commit/055a1531d313b889fc9f2cc45755bc9555348c65))

# [1.0.0-beta.48](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.47...v1.0.0-beta.48) (2024-05-23)


### Features

* add export routes support ([#50](https://github.com/ForestAdmin/agent-ruby/issues/50)) ([1377185](https://github.com/ForestAdmin/agent-ruby/commit/137718585056b38bfa29735e8075c13ab40c6230))

# [1.0.0-beta.47](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.46...v1.0.0-beta.47) (2024-05-22)


### Bug Fixes

* add emulate_field_filtering missing method on customizer ([#49](https://github.com/ForestAdmin/agent-ruby/issues/49)) ([41dfb0e](https://github.com/ForestAdmin/agent-ruby/commit/41dfb0eb8a27e7797057eeeed9ecd349dacda8f3))

# [1.0.0-beta.46](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.45...v1.0.0-beta.46) (2024-05-15)


### Features

* support multi field sorting from frontend ([#44](https://github.com/ForestAdmin/agent-ruby/issues/44)) ([eadde5d](https://github.com/ForestAdmin/agent-ruby/commit/eadde5d9d53ca56bbaf3f139780041e114f7c8a6))

# [1.0.0-beta.45](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.44...v1.0.0-beta.45) (2024-05-03)


### Features

* add logs in dev mode ([#43](https://github.com/ForestAdmin/agent-ruby/issues/43)) ([da941af](https://github.com/ForestAdmin/agent-ruby/commit/da941af365b1ca48832eaa32c7cf29880a5a66b7))

# [1.0.0-beta.44](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.43...v1.0.0-beta.44) (2024-05-02)


### Features

* add binary decorator support ([#42](https://github.com/ForestAdmin/agent-ruby/issues/42)) ([0e03047](https://github.com/ForestAdmin/agent-ruby/commit/0e0304753337fb8034ed2250d2c3d0a7b537b52e))
* add segment decorator support ([#41](https://github.com/ForestAdmin/agent-ruby/issues/41)) ([3b4e437](https://github.com/ForestAdmin/agent-ruby/commit/3b4e437460d7ac7d0c2eda291ddde241cff0fce9))

# [1.0.0-beta.43](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.42...v1.0.0-beta.43) (2024-04-12)


### Bug Fixes

* **security:** patch tar dependency vulnerabilities ([#40](https://github.com/ForestAdmin/agent-ruby/issues/40)) ([86be2a7](https://github.com/ForestAdmin/agent-ruby/commit/86be2a752011f469649cec0f09b55aa5939936d0))

# [1.0.0-beta.42](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.41...v1.0.0-beta.42) (2024-04-11)


### Features

* add hook decorator support ([#39](https://github.com/ForestAdmin/agent-ruby/issues/39)) ([1514aed](https://github.com/ForestAdmin/agent-ruby/commit/1514aed9a615fce2385fceea9099852e06f9e301))

# [1.0.0-beta.41](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.40...v1.0.0-beta.41) (2024-04-08)


### Bug Fixes

* rubocop lint ([#38](https://github.com/ForestAdmin/agent-ruby/issues/38)) ([48b658f](https://github.com/ForestAdmin/agent-ruby/commit/48b658f02949a29ed9a8f35beaa5d83ced6a8dfb))


### Features

* add chart decorator support ([#37](https://github.com/ForestAdmin/agent-ruby/issues/37)) ([c1fc0ac](https://github.com/ForestAdmin/agent-ruby/commit/c1fc0acb6109c396e500bf202d0e8eb20bc28943))

# [1.0.0-beta.40](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.39...v1.0.0-beta.40) (2024-04-05)


### Features

*  add write decorator support ([#36](https://github.com/ForestAdmin/agent-ruby/issues/36)) ([f052601](https://github.com/ForestAdmin/agent-ruby/commit/f0526015db0ddc83aa3ddf972628790fd0825575))

# [1.0.0-beta.39](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.38...v1.0.0-beta.39) (2024-03-22)


### Features

* add rename collection decorator support ([#35](https://github.com/ForestAdmin/agent-ruby/issues/35)) ([e0cad85](https://github.com/ForestAdmin/agent-ruby/commit/e0cad85b00e9b9335c8ff9c4bc062b77408bd42e))

# [1.0.0-beta.38](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.37...v1.0.0-beta.38) (2024-03-19)


### Features

* add publication decorator support ([#34](https://github.com/ForestAdmin/agent-ruby/issues/34)) ([7550e10](https://github.com/ForestAdmin/agent-ruby/commit/7550e10a50e99934776522e8650523413202f9b0))

# [1.0.0-beta.37](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.36...v1.0.0-beta.37) (2024-03-18)


### Features

* add rename field decorator support ([#33](https://github.com/ForestAdmin/agent-ruby/issues/33)) ([1bcfd42](https://github.com/ForestAdmin/agent-ruby/commit/1bcfd4294cc0df1e0cca29f7419e30dcc82d9d75))

# [1.0.0-beta.36](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.35...v1.0.0-beta.36) (2024-03-18)


### Features

* add sort decorator support ([#32](https://github.com/ForestAdmin/agent-ruby/issues/32)) ([a5320fc](https://github.com/ForestAdmin/agent-ruby/commit/a5320fca5a6b30d49ad1471fd9068ac7d65ed3e1))

# [1.0.0-beta.35](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.34...v1.0.0-beta.35) (2024-03-12)


### Features

* add operator emulate support ([#31](https://github.com/ForestAdmin/agent-ruby/issues/31)) ([fc6c7b5](https://github.com/ForestAdmin/agent-ruby/commit/fc6c7b5f3f31374936e89f84f69330433263904e))

# [1.0.0-beta.34](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.33...v1.0.0-beta.34) (2024-03-11)


### Features

* add validation support ([#30](https://github.com/ForestAdmin/agent-ruby/issues/30)) ([a0e8092](https://github.com/ForestAdmin/agent-ruby/commit/a0e80923ad1b75286d911ed96ef5e6baef0b022a))

# [1.0.0-beta.33](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.32...v1.0.0-beta.33) (2024-03-05)


### Features

* add relation decorator support  ([#29](https://github.com/ForestAdmin/agent-ruby/issues/29)) ([e181b5f](https://github.com/ForestAdmin/agent-ruby/commit/e181b5f82fb8a8b1fbf835545daa0145a219cea1))

# [1.0.0-beta.32](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.31...v1.0.0-beta.32) (2024-03-01)


### Features

* **action:** add permission on action routes ([#27](https://github.com/ForestAdmin/agent-ruby/issues/27)) ([c7361f7](https://github.com/ForestAdmin/agent-ruby/commit/c7361f753c40a8b4abfc4245aeb17f244c7fec02))

# [1.0.0-beta.31](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.30...v1.0.0-beta.31) (2024-02-22)


### Bug Fixes

* **security:** patch ip dependency vulnerabilities ([#28](https://github.com/ForestAdmin/agent-ruby/issues/28)) ([6988f97](https://github.com/ForestAdmin/agent-ruby/commit/6988f97f9eb549edde39277c3b9a1fbfe9364662))

# [1.0.0-beta.30](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.29...v1.0.0-beta.30) (2024-02-13)


### Features

* **decorator:** add action support ([#24](https://github.com/ForestAdmin/agent-ruby/issues/24)) ([e586476](https://github.com/ForestAdmin/agent-ruby/commit/e586476589c8f81fb741c5d11bd1f931c1d4e439))

# [1.0.0-beta.29](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.28...v1.0.0-beta.29) (2024-01-24)


### Features

* **decorator:** add compute support ([#23](https://github.com/ForestAdmin/agent-ruby/issues/23)) ([3345fb4](https://github.com/ForestAdmin/agent-ruby/commit/3345fb483c94296614a0f90251adba4845f1e90c))

# [1.0.0-beta.28](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.27...v1.0.0-beta.28) (2024-01-19)


### Features

* **serializer:** serialize hash instead of an active record object ([#22](https://github.com/ForestAdmin/agent-ruby/issues/22)) ([70dea37](https://github.com/ForestAdmin/agent-ruby/commit/70dea37982c201c3a547638f7b21cd0500b37014))

# [1.0.0-beta.27](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.26...v1.0.0-beta.27) (2024-01-02)


### Features

* **decorator:** add search support ([#21](https://github.com/ForestAdmin/agent-ruby/issues/21)) ([a71acc6](https://github.com/ForestAdmin/agent-ruby/commit/a71acc6391fe14d38fc7204c8942de4c95fcbd1f))

# [1.0.0-beta.26](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.25...v1.0.0-beta.26) (2024-01-02)


### Features

* **decorator:** add operators equivalence support  ([#20](https://github.com/ForestAdmin/agent-ruby/issues/20)) ([006c49a](https://github.com/ForestAdmin/agent-ruby/commit/006c49a1f1ac4c936b7a0ab9555ae81a884a0e5d))

# [1.0.0-beta.25](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.24...v1.0.0-beta.25) (2023-12-20)


### Features

* add schema decorator support ([#19](https://github.com/ForestAdmin/agent-ruby/issues/19)) ([3548290](https://github.com/ForestAdmin/agent-ruby/commit/354829022257d11aeb106ad760360adfe22bceff))

# [1.0.0-beta.24](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.23...v1.0.0-beta.24) (2023-12-18)


### Features

*  add customizer with decorator stack and empty-decorator ([#18](https://github.com/ForestAdmin/agent-ruby/issues/18)) ([900effd](https://github.com/ForestAdmin/agent-ruby/commit/900effd6f30218a7411e6858e13d72331cee6c15))

# [1.0.0-beta.23](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.22...v1.0.0-beta.23) (2023-12-13)


### Features

* add charts support ([#16](https://github.com/ForestAdmin/agent-ruby/issues/16)) ([a8d609f](https://github.com/ForestAdmin/agent-ruby/commit/a8d609fb4e1e963722debb7e36bd2f9f3e6c42de))

# [1.0.0-beta.22](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.21...v1.0.0-beta.22) (2023-12-08)


### Features

* add permissions support ([#17](https://github.com/ForestAdmin/agent-ruby/issues/17)) ([d7b14ca](https://github.com/ForestAdmin/agent-ruby/commit/d7b14ca8a32a049b8aabf47b0cbf1b165f3b7ad0))

# [1.0.0-beta.21](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.20...v1.0.0-beta.21) (2023-11-20)


### Bug Fixes

* ci deploy packages to rubygems ([75b32f5](https://github.com/ForestAdmin/agent-ruby/commit/75b32f5caa82216e8fe9d50d2f00c24ce7de841c))

# [1.0.0-beta.20](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.19...v1.0.0-beta.20) (2023-11-20)


### Bug Fixes

* ci deploy multiple packages ([d790bab](https://github.com/ForestAdmin/agent-ruby/commit/d790babff4cd5f9762cf3c6473e710c549fe9d79))

# [1.0.0-beta.19](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.18...v1.0.0-beta.19) (2023-11-20)


### Bug Fixes

* ci deploy packages ([9541ba0](https://github.com/ForestAdmin/agent-ruby/commit/9541ba0bb83842adfb13b43d74b1f2ad58d363ff))

# [1.0.0-beta.18](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.17...v1.0.0-beta.18) (2023-11-20)


### Bug Fixes

* ci ([0358208](https://github.com/ForestAdmin/agent-ruby/commit/0358208ae2631e9aec3874090e2ac1813d4ef60f))

# [1.0.0-beta.17](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.16...v1.0.0-beta.17) (2023-11-20)


### Bug Fixes

* ci deploy ([2f7653d](https://github.com/ForestAdmin/agent-ruby/commit/2f7653d520485ddc747a82126de0bb78f2341443))

# [1.0.0-beta.16](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.15...v1.0.0-beta.16) (2023-11-20)


### Bug Fixes

* ci releaserc deploy packages ([e9402a4](https://github.com/ForestAdmin/agent-ruby/commit/e9402a404a6b6021e847dbb9bed67e32e3922612))

# [1.0.0-beta.15](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.14...v1.0.0-beta.15) (2023-11-20)


### Bug Fixes

* ci setup credentials ([5a33f54](https://github.com/ForestAdmin/agent-ruby/commit/5a33f5436611470dcce01ab9f67a23ab28029c66))

# [1.0.0-beta.14](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.13...v1.0.0-beta.14) (2023-11-20)


### Bug Fixes

* comment out slack release ([9854f43](https://github.com/ForestAdmin/agent-ruby/commit/9854f430d46ef943c293ef1193c2c3e03a99c978))

# [1.0.0-beta.13](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.12...v1.0.0-beta.13) (2023-11-20)


### Bug Fixes

* ci deploy agent_ruby ([#15](https://github.com/ForestAdmin/agent-ruby/issues/15)) ([2ab162f](https://github.com/ForestAdmin/agent-ruby/commit/2ab162fff9b556433d8ad4f839fcfda0cd797e98))

# [1.0.0-beta.12](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.11...v1.0.0-beta.12) (2023-11-20)


### Bug Fixes

* ci remove rubygems_mfa_required ([#14](https://github.com/ForestAdmin/agent-ruby/issues/14)) ([848cdf9](https://github.com/ForestAdmin/agent-ruby/commit/848cdf9a590981b7b67adac93f6e51d87c6440f3))

# [1.0.0-beta.11](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.10...v1.0.0-beta.11) (2023-11-20)


### Bug Fixes

* deploy packages on rubygems ([#13](https://github.com/ForestAdmin/agent-ruby/issues/13)) ([ca07d9b](https://github.com/ForestAdmin/agent-ruby/commit/ca07d9b470da1b5fea8863b4bbfe8ffc22282836))

# [1.0.0-beta.10](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.9...v1.0.0-beta.10) (2023-11-16)


### Features

* add related routes ([#12](https://github.com/ForestAdmin/agent-ruby/issues/12)) ([78e5a04](https://github.com/ForestAdmin/agent-ruby/commit/78e5a0404a1e11f4ee16a9e69226c4b1c0028759))

# [1.0.0-beta.9](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.8...v1.0.0-beta.9) (2023-11-16)


### Bug Fixes

* **authentication:** return errors detail instead of generic error 500 ([#11](https://github.com/ForestAdmin/agent-ruby/issues/11)) ([19f84e5](https://github.com/ForestAdmin/agent-ruby/commit/19f84e54422ec6b0d2899621832023550e5d81a3))

# [1.0.0-beta.8](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.7...v1.0.0-beta.8) (2023-11-06)


### Features

* added filters feature ([#10](https://github.com/ForestAdmin/agent-ruby/issues/10)) ([9210563](https://github.com/ForestAdmin/agent-ruby/commit/92105633205c61679749f805bff23da6c88dd912))

# [1.0.0-beta.7](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.6...v1.0.0-beta.7) (2023-10-27)


### Features

* add all writing operations ([#9](https://github.com/ForestAdmin/agent-ruby/issues/9)) ([3fd6a7a](https://github.com/ForestAdmin/agent-ruby/commit/3fd6a7a9d1dbe21e8689f2d54ae9b9abf13c17a5))

# [1.0.0-beta.6](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.5...v1.0.0-beta.6) (2023-10-23)


### Features

* **engine:** improve setup agent ([#8](https://github.com/ForestAdmin/agent-ruby/issues/8)) ([8fb5c29](https://github.com/ForestAdmin/agent-ruby/commit/8fb5c29b3cb611f6847985c099d6a9bd33e442b3))

# [1.0.0-beta.5](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.4...v1.0.0-beta.5) (2023-10-13)


### Features

* add list and count api ([#6](https://github.com/ForestAdmin/agent-ruby/issues/6)) ([19b5bd9](https://github.com/ForestAdmin/agent-ruby/commit/19b5bd9ebb121f4c40e11f340d914dee4a84dc68))

# [1.0.0-beta.4](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.3...v1.0.0-beta.4) (2023-10-12)


### Features

* add ipwhitelist support ([#7](https://github.com/ForestAdmin/agent-ruby/issues/7)) ([680a17d](https://github.com/ForestAdmin/agent-ruby/commit/680a17dd8642d345444ef39d32285847c7992043))

# [1.0.0-beta.3](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.2...v1.0.0-beta.3) (2023-10-06)


### Features

* add jsonapi serializer ([#5](https://github.com/ForestAdmin/agent-ruby/issues/5)) ([3528191](https://github.com/ForestAdmin/agent-ruby/commit/35281919260084dbe20b32e2e3cd7f5ee1cdc54b))

# [1.0.0-beta.2](https://github.com/ForestAdmin/agent-ruby/compare/v1.0.0-beta.1...v1.0.0-beta.2) (2023-09-29)


### Features

* add forestadmin schema generate ([#4](https://github.com/ForestAdmin/agent-ruby/issues/4)) ([329397b](https://github.com/ForestAdmin/agent-ruby/commit/329397b4218373037d031607c763d81fe3126465))

# 1.0.0-beta.1 (2023-09-27)


### Features

* add authentication  ([#3](https://github.com/ForestAdmin/agent-ruby/issues/3)) ([ce369fd](https://github.com/ForestAdmin/agent-ruby/commit/ce369fd8999d048150d733332d5806d8678e7a14))

## [Unreleased]

## [0.1.0] - 2023-08-28

- Initial release
