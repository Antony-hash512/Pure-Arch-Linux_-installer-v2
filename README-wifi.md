Чтобы подключиться к Wi-Fi в TTY, если установлен `NetworkManager`, можно использовать команду `nmcli`. Вот пошаговая инструкция:

1. **Узнать доступные сети:**
   ```bash
   nmcli device wifi list
   ```
   Эта команда покажет список доступных Wi-Fi сетей.

2. **Подключиться к Wi-Fi сети:**
   ```bash
   nmcli device wifi connect "SSID" password "PASSWORD"
   ```
   Замените `"SSID"` на имя вашей Wi-Fi сети, а `"PASSWORD"` на пароль от сети.

   Например:
   ```bash
   nmcli device wifi connect "MyNetwork" password "SuperSecretPassword"
   ```

3. **Проверить статус подключения:**
   После выполнения команды можно проверить, подключились ли вы успешно, с помощью команды:
   ```bash
   nmcli connection show --active
   ```
   Если вы видите подключение с типом `wifi`, значит соединение установлено успешно.

Эти команды должны работать в любом терминале, включая TTY, если `NetworkManager` установлен и запущен.
