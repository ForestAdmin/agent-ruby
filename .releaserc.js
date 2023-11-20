module.exports = {
  branches: ['main', {name: 'beta', prerelease: true}],
  plugins: [
    [
      '@semantic-release/commit-analyzer', {
        preset: 'angular',
        releaseRules: [
          // Example: `type(scope): subject [force release]`
          { subject: '*\\[force release\\]*', release: 'patch' },
        ],
      },
    ],
    '@semantic-release/release-notes-generator',
    '@semantic-release/changelog',
    [
      '@semantic-release/exec',
      {
        prepareCmd:
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' lib/agent_ruby/version.rb; ' +
            'sed -i \'s/"version": ".*"/"version": "${nextRelease.version}"/g\' package.json; ' +
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forest_admin_agent/lib/forest_admin_agent/version.rb; ' +
            'sed -i \'s/LIANA_VERSION = ".*"/LIANA_VERSION = "${nextRelease.version}"/g\' packages/forest_admin_agent/lib/forest_admin_agent/utils/schema/schema_emitter.rb; ' +
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forest_admin_datasource_active_record/lib/forest_admin_datasource_active_record/version.rb; '+
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forest_admin_datasource_toolkit/lib/forest_admin_datasource_toolkit/version.rb; '+
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forest_admin_rails/lib/forest_admin_rails/version.rb; ',
        successCmd:
            'cd packages/forest_admin_agent && gem build && touch .trigger-rubygem-release;' +
            'cd packages/forest_admin_datasource_active_record && gem build && touch .trigger-rubygem-release;' +
            'cd packages/forest_admin_datasource_toolkit && gem build && touch .trigger-rubygem-release;' +
            'cd packages/forest_admin_rails && gem build && touch .trigger-rubygem-release;' ,
      },
    ],
    [
      '@semantic-release/git',
      {
        assets: [
          'CHANGELOG.md',
          'lib/agent_ruby/version.rb',
          'packages/forest_admin_agent/lib/forest_admin_agent/version.rb',
          'packages/forest_admin_agent/lib/forest_admin_agent/utils/schema/schema_emitter.rb',
          'packages/forest_admin_datasource_active_record/lib/forest_admin_datasource_active_record/version.rb',
          'packages/forest_admin_datasource_toolkit/lib/forest_admin_datasource_toolkit/version.rb',
          'packages/forest_admin_rails/lib/forest_admin_rails/version.rb',
          'package.json'
        ],
      },
    ],
    '@semantic-release/github',
    'semantic-release-rubygem',
    // [
    //   'semantic-release-slack-bot',
    //   {
    //     markdownReleaseNotes: true,
    //     notifyOnSuccess: true,
    //     notifyOnFail: false,
    //     onSuccessTemplate: {
    //       text: "📦 $package_name@$npm_package_version has been released!",
    //       blocks: [{
    //         type: 'section',
    //         text: {
    //           type: 'mrkdwn',
    //           text: '*New `$package_name` package released!*'
    //         }
    //       }, {
    //         type: 'context',
    //         elements: [{
    //           type: 'mrkdwn',
    //           text: "📦  *Version:* <$repo_url/releases/tag/v$npm_package_version|$npm_package_version>"
    //         }]
    //       }, {
    //         type: 'divider',
    //       }],
    //       attachments: [{
    //         blocks: [{
    //           type: 'section',
    //           text: {
    //             type: 'mrkdwn',
    //             text: '*Changes* of version $release_notes',
    //           },
    //         }],
    //       }],
    //     },
    //     packageName: 'agent_ruby',
    //   }
    // ],
  ],
}
