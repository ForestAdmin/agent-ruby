class ForestAdminErrorSubscriber
  SEVERITY_TO_LEVEL = {
    error: 'Error',
    warning: 'Warn',
    info: 'Info'
  }.freeze

  def report(error, handled:, severity:, context:, source: nil)
    level = SEVERITY_TO_LEVEL.fetch(severity, 'Error')
    ForestAdminAgent::Facades::Container.logger.log(level, "[ForestAdmin] #{error.full_message}")
  end
end
