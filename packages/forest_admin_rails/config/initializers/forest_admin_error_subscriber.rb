class ForestAdminErrorSubscriber
  def report(error, _handled:, _severity:, _context:, _source: nil)
    return if ForestAdminAgent::Facades::Container.cache(:is_production)

    ForestAdminAgent::Facades::Container.logger.log('Debug', error.full_message)
  end
end
