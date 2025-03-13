### Requirements

Make sure that:

- You have a database postgres and a mysql database.
- You have create a `.env` contains a valid `forest_env_secret` based on `.env.example`.

## Installation

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

