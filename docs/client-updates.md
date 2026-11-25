# Обновление клиента

Игрок запускает `AuctionLauncher.exe`, а не `Auction.exe` напрямую.

Launcher проверяет манифест `https://www.arh.seaetr.online/updates/latest.json`, сравнивает версии, скачивает ZIP-архив и проверяет его SHA-256. Архив обновления должен содержать файлы игры внутри папки `game/`.

При выпуске новой версии:

1. Увеличить `config/version` в `project.godot`.
2. Экспортировать игру в `auction_build`.
3. Собрать ZIP с `game/Auction.exe` и `game/Auction.pck`.
4. Вычислить SHA-256 архива.
5. Обновить `server/updates/latest.json`.
6. Загрузить ZIP и манифест в `/opt/auction/server/updates/`.
7. Перезапустить сервер.

Пользовательские данные Godot из `user://` не входят в обновление и сохраняются.
