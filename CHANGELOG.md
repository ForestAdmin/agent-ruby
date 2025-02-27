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
