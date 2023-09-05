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
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forestadmin_agent/lib/forestadmin_agent/version.rb; ' +
            'sed -i \'s/VERSION = ".*"/VERSION = "${nextRelease.version}"/g\' packages/forestadmin_rails/lib/forestadmin_rails/version.rb; ',
        successCmd:
            'mkdir -p $HOME/.gem '+
            'touch $HOME/.gem/credentials '+
            'chmod 0600 $HOME/.gem/credentials '+
            'printf -- "---\n:rubygems_api_key: ${env.GEM_HOST_API_KEY}\n" > $HOME/.gem/credentials '+
            '( cd packages/forestadmin_agent && gem build && gem push forestadmin_agent-${nextRelease.version}.gem )' +
            '( cd packages/forestadmin_rails && gem build && gem push forestadmin_rails-${nextRelease.version}.gem )' ,
      },
    ],
    [
      '@semantic-release/git',
      {
        assets: [
          'CHANGELOG.md',
          'lib/agent_ruby/version.rb',
          'packages/forestadmin_agent/lib/forestadmin_agent/version.rb',
          'packages/forestadmin_rails/lib/forestadmin_rails/version.rb',
          'package.json'
        ],
      },
    ],
    '@semantic-release/github',
    'semantic-release-rubygem',
    [
      'semantic-release-slack-bot',
      {
        markdownReleaseNotes: true,
        notifyOnSuccess: true,
        notifyOnFail: false,
        onSuccessTemplate: {
          text: "📦 $package_name@$npm_package_version has been released!",
          blocks: [{
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: '*New `$package_name` package released!*'
            }
          }, {
            type: 'context',
            elements: [{
              type: 'mrkdwn',
              text: "📦  *Version:* <$repo_url/releases/tag/v$npm_package_version|$npm_package_version>"
            }]
          }, {
            type: 'divider',
          }],
          attachments: [{
            blocks: [{
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: '*Changes* of version $release_notes',
              },
            }],
          }],
        },
        packageName: 'agent_ruby',
      }
    ],
  ],
}
