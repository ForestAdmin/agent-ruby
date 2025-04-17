### Requirements

Make sure that:

- You have a database postgres and a mysql database.
- You have create a `.env` contains a valid `forest_env_secret` based on `.env.example`.

## Installation

# 1. Construire les conteneurs
docker compose build

# 2. Démarrer les services
docker compose up -d


Install the requirements

```
bundle install
```

Generate the Master Key (Only if it's your first install)

```
bin/rails credentials:edit
```

Apply the migrations

```
bin/rails db:migrate
```

Apply the seeds

```
bin/rails db:seed
```

Run the app

```
rails server
```
