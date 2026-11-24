# PostgreSQL migration

Для локального запуска:

```powershell
docker compose -f server/docker-compose.yml up -d postgres
$env:DATABASE_URL = "postgresql://auction:auction_dev_password@127.0.0.1:5432/auction"
node server/index.js
```

`schema.sql` подключается контейнером автоматически при первом создании тома. В приложении добавлен `withTransaction(pool, callback)` для денежных операций: списание, резервирование ставки и перевод предмета должны выполняться внутри одной транзакции.
