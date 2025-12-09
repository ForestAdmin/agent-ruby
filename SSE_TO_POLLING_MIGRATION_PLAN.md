# Migration SSE vers Polling - Plan détaillé

**Date:** 2025-12-09
**Branch:** `feature/replace-sse-with-polling`
**Objectif:** Remplacer le système SSE (Server-Sent Events) par un système de polling HTTP simple

---

## Résumé exécutif

### Problèmes SSE actuels
- **Connexions zombies** malgré le SseConnectionManager
- **Auth expirée** lors des reconnexions
- **Complexité** élevée (~1000+ lignes de code + tests)
- **Dépendance externe** `ld-eventsource` avec bugs
- **3 commits de fix majeurs** en décembre 2025 sans résoudre tous les problèmes

### Solution proposée
- **Polling HTTP simple** toutes les 30 secondes sur un endpoint `/forest/health`
- **Détection de server down** après 3 échecs consécutifs (~90s max)
- **Pas de connexion persistante**, pas de problèmes d'auth expirée
- **Simplicité** maximale avec GET requests standards

### Trade-off acceptable
- **Latence de détection:** Instantané (SSE) → ~90 secondes max (polling)
- **Contexte:** Détection de shutdown de RPC server (événement rare, latence acceptable)

---

## Architecture actuelle SSE

### Côté RPC Agent (Server)
```
packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/
├── routes/sse.rb                    # Route GET /forest/sse (167 lignes)
├── sse_connection_manager.rb        # Gestion single connection (82 lignes)
└── sse_streamer.rb                  # Format SSE events (15 lignes)
```

**Fonctionnement:**
- Route `/forest/sse` avec auth HMAC-SHA256
- Stream `text/event-stream` avec heartbeat toutes les 10s
- Event `RpcServerStop` sur SIGINT/SIGTERM
- SseConnectionManager termine les connexions zombies

### Côté RPC Datasource (Client)
```
packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/
├── forest_admin_datasource_rpc.rb   # Setup SSE + signal handlers (99 lignes)
├── datasource.rb                     # Intégration datasource (74 lignes)
└── Utils/sse_client.rb               # Client avec reconnect (213 lignes)
```

**Fonctionnement:**
- SseClient se connecte au stream SSE
- Reconnexion exponentielle (2s → 30s max)
- Callback `on_rpc_stop` → check schema → reload si changé
- Signal handlers pour cleanup

### Dépendances
- **Gem:** `ld-eventsource ~> 2.2` (dans 2 gemspecs)
- Utilisée uniquement pour le client SSE

---

## Tests SSE existants (Documentation complète)

### 1. Routes::Sse spec (~364 lignes)
**Fichier:** `packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/routes/sse_spec.rb`

**Tests critiques à reproduire:**
- ✅ Initialisation avec valeurs par défaut (url, method, name, heartbeat_interval=10)
- ✅ Initialisation avec paramètres custom
- ✅ NotImplementedError pour apps non supportées
- ✅ Enregistrement pour Rails (ActionDispatch::Routing::Mapper)
- ✅ Enregistrement pour Sinatra (Sinatra::Base)
- ✅ Streaming de heartbeat events
- ✅ Headers corrects:
  - Content-Type: text/event-stream
  - Cache-Control: no-cache
  - Connection: keep-alive
  - X-Accel-Buffering: no
- ✅ Custom heartbeat interval respecté
- ✅ Logs de stream start/stop
- ✅ Gestion IOError (client disconnect)
- ✅ Auth middleware: retourne 401 si auth invalide
- ✅ Intégration SseConnectionManager:
  - Enregistre la connexion
  - Termine connexion précédente sur nouvelle requête
  - Utilise connection.active? comme condition de loop

**Total tests:** 12 tests

---

### 2. SseConnectionManager spec (~169 lignes)
**Fichier:** `packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/sse_connection_manager_spec.rb`

**Tests critiques à reproduire:**
- ✅ register_connection retourne une Connection
- ✅ Connection est active par défaut
- ✅ current_connection est set
- ✅ Termine connexion précédente sur nouvelle registration
- ✅ Logs des opérations (terminating, registered, unregistered)
- ✅ unregister_connection clear si match
- ✅ unregister_connection ne clear pas si pas de match
- ✅ reset! termine et clear
- ✅ Thread-safety: 10 threads concurrent → 1 seule active
- ✅ Connection.id est unique (UUID)
- ✅ Connection.active? et terminate
- ✅ terminate est idempotent

**Total tests:** 15 tests

---

### 3. SseClient spec (~497 lignes)
**Fichier:** `packages/forest_admin_datasource_rpc/spec/lib/forest_admin_datasource_rpc/utils/sse_client_spec.rb`

**Tests critiques à reproduire pour HealthCheckClient:**
- ✅ Initialisation avec uri, secret, callback
- ✅ Expose closed status
- ✅ start() se connecte avec headers HMAC:
  - Accept: text/event-stream (pas nécessaire pour polling)
  - X_TIMESTAMP: timestamp ISO8601
  - X_SIGNATURE: HMAC-SHA256
- ✅ start() n'essaie pas si déjà closed
- ✅ Incrémente connection_attempts
- ✅ Logs de connexion avec attempt number
- ✅ Logs de succès
- ✅ Logs d'erreur et schedule reconnect
- ✅ close() ferme le client
- ✅ close() est idempotent
- ✅ close() logs closing/closed
- ✅ close() gère les erreurs gracefully
- ✅ close() set closed flag
- ✅ close() stop le reconnect thread
- ✅ handle_event pour RpcServerStop → callback
- ✅ handle_event pour heartbeat → reset connecting flag (adaptation polling: success)
- ✅ handle_event pour unknown events → logs
- ✅ handle_error avec différents types:
  - StandardError → Warn
  - EOFError/IOError → Debug (connection lost)
  - HTTP 401/403 → Debug (auth error)
- ✅ handle_error ignore si closed
- ✅ handle_error close client et schedule reconnect
- ✅ schedule_reconnect crée thread
- ✅ schedule_reconnect ne crée pas si thread alive
- ✅ schedule_reconnect ne fait rien si closed
- ✅ calculate_backoff_delay exponentiel: 2, 4, 8, 16, 30 (cap)
- ✅ attempt_connection ne tente pas si déjà connecting
- ✅ attempt_connection close existing client avant new
- ✅ handle_rpc_stop execute callback (adaptation: on_server_down)
- ✅ handle_rpc_stop gère callback errors
- ✅ handle_rpc_stop gère nil callback
- ✅ generate_signature HMAC correct

**Total tests:** 32 tests

---

## Plan de migration par phase

### Phase 1: Préparation ✅ (30 min)
**Status:** COMPLETED
- ✅ Analyse SSE complète
- ✅ Création branche `feature/replace-sse-with-polling`
- ✅ Documentation tests existants
- ✅ Plan de migration créé

**Tests:** Tous les tests existants passent

---

### Phase 2: Endpoint Health Check (RPC Agent) (1h)

**Fichiers à créer:**
```
packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/routes/
└── health.rb                          # ~50 lignes

packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/routes/
└── health_spec.rb                     # ~150 lignes
```

**Implémentation `Routes::Health`:**
```ruby
module ForestAdminRpcAgent
  module Routes
    class Health
      def initialize(url = 'health', method = 'get', name = 'rpc_health')
        @url = url
        @method = method
        @name = name
      end

      def registered(app)
        # Support Rails et Sinatra comme Routes::Sse
      end

      def register_rails(router)
        # GET /forest/health
        # Auth HMAC-SHA256
        # Retourne: { status: "ok", version: VERSION }
      end

      def register_sinatra(app)
        # Idem pour Sinatra
      end
    end
  end
end
```

**Tests à écrire (~10 tests):**
- ✅ Initialisation avec valeurs par défaut
- ✅ Enregistrement Rails/Sinatra
- ✅ Route accessible en GET
- ✅ Auth HMAC requise (401 si invalid)
- ✅ Retourne JSON { status: "ok" }
- ✅ Headers corrects (Content-Type: application/json)
- ✅ Logs des requêtes

**Critères de succès:**
- `bundle exec rspec packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/routes/health_spec.rb` → 100% pass
- Route testable manuellement avec curl

---

### Phase 3: HealthCheckClient (RPC Datasource) (2h)

**Fichiers à créer:**
```
packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/Utils/
└── health_check_client.rb             # ~200 lignes

packages/forest_admin_datasource_rpc/spec/lib/forest_admin_datasource_rpc/utils/
└── health_check_client_spec.rb        # ~500 lignes
```

**Implémentation `HealthCheckClient`:**
```ruby
module ForestAdminDatasourceRpc
  module Utils
    class HealthCheckClient
      attr_reader :closed

      DEFAULT_POLLING_INTERVAL = 30      # secondes
      DEFAULT_FAILURE_THRESHOLD = 3      # échecs consécutifs
      MAX_BACKOFF_DELAY = 30
      INITIAL_BACKOFF_DELAY = 2

      def initialize(uri, auth_secret, options = {}, &on_server_down)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = options[:polling_interval] || DEFAULT_POLLING_INTERVAL
        @failure_threshold = options[:failure_threshold] || DEFAULT_FAILURE_THRESHOLD
        @on_server_down = on_server_down
        @closed = false
        @consecutive_failures = 0
        @polling_thread = nil
        @http_client = Faraday.new(...)
      end

      def start
        # Lance thread de polling
      end

      def stop
        # Arrête le thread et ferme connexions
      end

      private

      def polling_loop
        # Loop infinie qui:
        # 1. Fait GET sur @uri avec HMAC auth
        # 2. Si success → reset consecutive_failures
        # 3. Si échec → incremente consecutive_failures
        # 4. Si consecutive_failures >= threshold → trigger callback
        # 5. Sleep @polling_interval
      end

      def check_health
        # GET @uri avec HMAC headers
        # Retourne true/false
      end

      def handle_failure(error)
        # Incremente failures
        # Logs
        # Trigger callback si threshold atteint
      end

      def generate_signature(timestamp)
        # HMAC-SHA256 comme SseClient
      end
    end
  end
end
```

**Tests à écrire (~30 tests basés sur SseClient):**
- Tous les tests SseClient adaptés pour polling
- Tests spécifiques au polling:
  - ✅ Poll à l'intervalle configuré
  - ✅ Détecte server down après N échecs
  - ✅ Reset failures sur success
  - ✅ Ne trigger callback qu'une fois (pas à chaque échec après threshold)

**Critères de succès:**
- `bundle exec rspec packages/forest_admin_datasource_rpc/spec/lib/forest_admin_datasource_rpc/utils/health_check_client_spec.rb` → 100% pass
- Code coverage ≥ 95%

---

### Phase 4: Intégration Datasource (1h30)

**Fichiers à modifier:**
```
packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/
├── forest_admin_datasource_rpc.rb     # Remplacer SseClient par HealthCheckClient
└── datasource.rb                       # Adapter cleanup
```

**Modifications `forest_admin_datasource_rpc.rb` (ligne 46-56):**
```ruby
# AVANT:
sse = Utils::SseClient.new("#{uri}/forest/sse", auth_secret) do
  # ... callback ...
end
sse.start

# APRÈS:
health_check = Utils::HealthCheckClient.new(
  "#{uri}/forest/health",
  auth_secret,
  polling_interval: options[:health_check_interval] || 30,
  failure_threshold: options[:health_check_failure_threshold] || 3
) do
  # ... même callback ...
end
health_check.start
```

**Modifications `datasource.rb` (ligne 21, 56-71):**
```ruby
# Remplacer @sse_client par @health_check_client
# Adapter cleanup method
```

**Tests à adapter:**
- Tous les tests d'intégration datasource

**Critères de succès:**
- `bundle exec rspec packages/forest_admin_datasource_rpc/spec/` → 100% pass
- Datasource démarre et détecte server down correctement

---

### Phase 5: Tests d'intégration (1h)

**Objectif:** Valider avec l'exemple warehouse

**Fichiers:**
```
packages/_examples/warehouse/
```

**Tests manuels:**
1. Démarrer le warehouse (RPC Agent)
2. Démarrer un master avec RPC Datasource
3. Vérifier les logs de polling
4. Arrêter le warehouse
5. Vérifier la détection de shutdown (~90s)
6. Redémarrer le warehouse
7. Vérifier la recovery
8. Modifier le schema
9. Vérifier le reload

**Critères de succès:**
- Tous les scénarios fonctionnent
- Logs propres, pas d'erreurs
- Détection < 2 minutes

---

### Phase 6: Supprimer code SSE (RPC Agent) (30 min)

**Fichiers à supprimer:**
```
packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/
├── routes/sse.rb
├── sse_connection_manager.rb
└── sse_streamer.rb

packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/
├── routes/sse_spec.rb
└── sse_connection_manager_spec.rb
```

**Fichiers à modifier:**
- Retirer enregistrement route SSE dans l'agent

**Critères de succès:**
- `bundle exec rspec packages/forest_admin_rpc_agent/spec/` → 100% pass
- Pas de références SSE résiduelles

---

### Phase 7: Supprimer code SSE (RPC Datasource) (30 min)

**Fichiers à supprimer:**
```
packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/Utils/
└── sse_client.rb

packages/forest_admin_datasource_rpc/spec/lib/forest_admin_datasource_rpc/utils/
└── sse_client_spec.rb
```

**Critères de succès:**
- `bundle exec rspec packages/forest_admin_datasource_rpc/spec/` → 100% pass
- Pas de références SSE

---

### Phase 8: Supprimer dépendance ld-eventsource (30 min)

**Fichiers à modifier:**
```
packages/forest_admin_datasource_rpc/forest_admin_datasource_rpc.gemspec
packages/forest_admin_agent/forest_admin_agent.gemspec
```

**Actions:**
```bash
# Retirer spec.add_dependency "ld-eventsource", "~> 2.2"
cd packages/forest_admin_datasource_rpc
bundle install

cd ../forest_admin_rpc_agent
bundle install
```

**Note:** Vérifier si `forest_admin_agent/services/sse_cache_invalidation.rb` utilise SSE (scope différent: ForestAdmin server, pas RPC). Si oui, migration séparée.

**Critères de succès:**
- `bundle install` réussit partout
- Pas de `ld-eventsource` dans les Gemfile.lock
- Tous les tests passent

---

### Phase 9: Documentation et tests E2E (1h30)

**Fichiers à créer/modifier:**
```
CHANGELOG.md
README.md (si nécessaire)
SSE_TO_POLLING_MIGRATION.md (historique)
```

**Tests E2E complets:**
- Scénario nominal
- Shutdown/restart multiples
- Schema changes
- Multiples datasources RPC simultanées
- Performance (CPU, mémoire)

**Métriques à mesurer:**
- Temps de détection de shutdown
- Overhead CPU/mémoire du polling
- Temps de schema reload

**Critères de succès:**
- Tous les tests E2E passent
- Documentation complète
- Metrics acceptables

---

## Plan de rollback

### Si problème en Phase 2-4 (code SSE existe encore)
```bash
# Simplement abandonner la branche et revenir à main
git checkout main
git branch -D feature/replace-sse-with-polling
```

### Si problème en Phase 5-9 (code SSE supprimé)
```bash
# Revert le commit de suppression SSE
git log --oneline  # Trouver le commit
git revert <commit-hash>

# Ou recréer les fichiers depuis l'historique
git show main:packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/routes/sse.rb > ...
```

### Si problème en production après merge
1. **Hotfix:** Revert du merge dans une nouvelle branche `hotfix/revert-polling`
2. **Release:** Version patch avec revert
3. **Analyse:** Investigation de la cause root
4. **Fix forward:** Corriger le problème et re-déployer le polling

---

## Estimation de l'effort

| Phase | Durée estimée | Tests | Critique |
|-------|--------------|-------|----------|
| Phase 1 | 30 min | ✅ Passent | Non |
| Phase 2 | 1h | ~10 tests | Oui |
| Phase 3 | 2h | ~30 tests | Oui |
| Phase 4 | 1h30 | Existants | Oui |
| Phase 5 | 1h | Manuels | Oui |
| Phase 6 | 30 min | Existants | Non |
| Phase 7 | 30 min | Existants | Non |
| Phase 8 | 30 min | Existants | Non |
| Phase 9 | 1h30 | E2E | Oui |
| **Total** | **10h** | **~50 tests** | - |

---

## Risques et mitigation

### Risque 1: Détection trop lente (>2 min)
**Mitigation:** Polling interval configurable (default 30s, peut être réduit à 10s)

### Risque 2: Callback pas appelé
**Mitigation:** Tests exhaustifs du failure threshold

### Risque 3: Fuite mémoire des threads
**Mitigation:** Cleanup rigoureux dans stop(), tests de ressources

### Risque 4: Auth HMAC invalide
**Mitigation:** Réutiliser exactement le même code que SseClient

### Risque 5: Race conditions
**Mitigation:** Mutex pour thread-safety, tests de concurrence

---

## Changements de comportement

### Pour les utilisateurs
| Avant (SSE) | Après (Polling) |
|------------|-----------------|
| Détection instantanée shutdown | Détection en ~90s max |
| Connexion persistante | Pas de connexion persistante |
| Problèmes auth expirée | Pas de problèmes auth |
| Connexions zombies | Pas de connexions zombies |
| Gem externe ld-eventsource | HTTP natif (Faraday) |

### Configuration
```ruby
# AVANT:
ForestAdminDatasourceRpc.build(
  uri: 'http://localhost:3000',
  auth_secret: 'secret'
)

# APRÈS: (backward compatible)
ForestAdminDatasourceRpc.build(
  uri: 'http://localhost:3000',
  auth_secret: 'secret',
  health_check_interval: 30,           # OPTIONNEL (default: 30s)
  health_check_failure_threshold: 3    # OPTIONNEL (default: 3)
)
```

---

## Checklist finale

### Avant merge
- [ ] Toutes les phases complétées
- [ ] Tous les tests passent (RSpec)
- [ ] Tests E2E passent
- [ ] Code review complet
- [ ] Documentation à jour
- [ ] CHANGELOG.md mis à jour
- [ ] Pas de références SSE résiduelles
- [ ] Gem ld-eventsource supprimée
- [ ] Performance acceptable

### Après merge
- [ ] CI/CD passe
- [ ] Déploiement en staging
- [ ] Tests de validation staging
- [ ] Monitoring des métriques
- [ ] Déploiement en production
- [ ] Monitoring 24h post-deploy

---

## Contacts et ressources

**Documentation externe:**
- SSE spec: https://html.spec.whatwg.org/multipage/server-sent-events.html
- ld-eventsource gem: https://github.com/launchdarkly/ruby-eventsource

**Commits historiques SSE:**
- `c7b65e9` - fix(rpc): ensure single SSE connection to master
- `1dc23da` - chore: increase SSE heartbeat interval from 1s to 10s
- `a5b306c` - fix(rpc): properly cleanup SSE connections and handle shutdown signals

**Branch:** `feature/replace-sse-with-polling`
**Date création:** 2025-12-09
**Auteur:** Claude Code
