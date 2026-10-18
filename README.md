# Yeelight Bilina — poprawka oryginalnej integracji SignalRGB

Ta wersja jest **nakładką na oficjalny dodatek** [SignalRGB/Yeelight](https://gitlab.com/signalrgb/yeelight) — nie nową implementacją protokołu. Zachowuje oryginalną obsługę animacji, wykrywania SSDP, UDP 55444 i komponentów.

## Instalacja (Windows 10/11)

1. Zamknij SignalRGB **całkowicie**, również obok zegara.
2. Pobierz [ZIP tego repozytorium](https://github.com/bilinabilinski/signalrgb-yeelight-bilina/archive/refs/heads/main.zip).
3. Wybierz **Wyodrębnij wszystkie** (nie uruchamiaj plików bezpośrednio z ZIP).
4. Uruchom `INSTALL.cmd` z rozpakowanego folderu.
5. Instalator pobierze źródła **bezpośrednio z oficjalnego GitLaba**, zastosuje poprawki i umieści dodatek w `Dokumenty\WhirlwindFX\Plugins\YeelightBilina`.
6. Uruchom SignalRGB, wyłącz starsze testowe dodatki ColorC i sprawdź usługę **Yeelight Bilina**. W logach szukaj `[Bilina] Yeelight upstream-based fix v1.0.2 active`.

**Uwaga:** Wtyczka z naszego repozytorium nie instaluje się przez samo `Check for Updates` w SignalRGB. Instaluje ją skrypt `INSTALL.cmd`.

## Powrót do białego światła po zamknięciu SignalRGB (v1.0.2)

Dla żarówek Yeelight GU10 W1 Color (`colorc`) podczas **zwykłego zamknięcia** SignalRGB wtyczka automatycznie wysyła:
- `set_power: on`;
- `set_bright: 100`;
- `set_rgb: 16777215` (biały `#FFFFFF`).

Działa to niezależnie od wcześniej zapamiętanej opcji `Turn off on unlink process`. Na czas zawieszenia systemu zachowano dotychczasowe wygaszanie. Dla modeli innych niż `colorc` pozostaje oryginalne działanie.

**Uwaga:** `#FFFFFF` jest bielą RGB, nie gwarantuje powrotu do *dokładnie* wcześniejszej temperatury barwowej (Kelvinów), jasności ani trybu dedykowanych białych diod. Te parametry wymagają oddzielnej obsługi trybu `set_ct_abx` i informacji o ustawieniu użytkownika. Mechanizm `Shutdown()` wywoływany jest przy **normalnym zamknięciu** programu lub wyłączeniu streamingu. Przymusowe zakończenie procesu może uniemożliwić wykonanie poleceń.

Aby wgrać poprawkę, pobierz ponownie **najnowszy ZIP** repozytorium, rozpakuj i uruchom `INSTALL.cmd`. Poprzednia kopia wtyczki jest zachowywana jako folder backup.

## Automatyczny powrót do prawdziwej bieli po zamknięciu SignalRGB

**Zalecane rozwiązanie dla GU10 W1 Color (`colorc`):** wtyczka SignalRGB nie zawsze ma czas przesłać pakiety podczas zamykania aplikacji. Dlatego dodany jest **opcjonalny, niezależny proces Windows**, który wykrywa zakończenie `SignalRGB.exe` i następnie przywraca natywny tryb bieli Yeelight przez TCP 55443.

### Instalacja

1. Pobierz [ZIP z repozytorium](https://github.com/bilinabilinski/signalrgb-yeelight-bilina/archive/refs/heads/main.zip) i wybierz **Wyodrębnij wszystkie**.
2. Pozostaw działającą dotychczasową wtyczkę `Yeelight Bilina`. **Nie trzeba jej reinstalować.**
3. Z rozpakowanego folderu uruchom **`INSTALL_WHITE_RESTORE.cmd`**.
4. Mechanizm uruchomi się w tle i będzie automatycznie startował przy logowaniu użytkownika.
5. Otwórz SignalRGB, ustaw kolorowy efekt, następnie zamknij **Quit/Exit**. Po około 5–10 sekundach wszystkie trzy żarówki powinny wrócić do bieli.

Domyślne urządzenia: `192.168.1.149`, `192.168.1.150`, `192.168.1.153`. Komendy: `set_power(on)`, `set_ct_abx(4000 K)`, `set_bright(100%)`, z potwierdzeniem odpowiedzi `result: ["ok"]`. Przy błędzie nieudane żarówki są ponawiane maksymalnie dziewięć razy (przez około 45 sekund), aby dać czas na wygaśnięcie sesji UDP.

**Test diagnostyczny:** zamknij SignalRGB przez Exit i uruchom `TEST_WHITE_RESTORE.cmd`. Ten test wysyła biel natychmiast, bez czekania na zamknięcie programu. Jeśli nie działa, przyczyną nie jest wykrywanie zakończenia programu. Wyślij log `%LOCALAPPDATA%\YeelightBilina\white-restore.log` — pokaże odpowiedź połączenia TCP lub błąd.

**Zmiana odcienia bieli:** edytuj `%LOCALAPPDATA%\YeelightBilina\white-restore.json`, np. `"kelvin": 2700` dla ciepłej bieli lub `"kelvin": 5000` dla chłodniejszej; dopuszczalny zakres 2700–6500 K. Możesz też zmienić `"brightness"` (1–100) i listę `"ips"`.

**Wyłączenie:** uruchom `UNINSTALL_WHITE_RESTORE.cmd`. Usuwa skrót autostartu oraz zatrzymuje watcher w ciągu kilku sekund. Zachowuje log i konfigurację.

**Ważne:** zainstalowany mechanizm to niewielki skrypt PowerShell uruchomiony w tle przez skrót w autostarcie Windows — nie ingeruje w efekty SignalRGB podczas działania programu. Nie wymaga uprawnień administratora. Działa po normalnym zakończeniu procesu aplikacji, ale nie po odłączeniu zasilania komputera ani w czasie uśpienia systemu. Nie przywraca automatycznie dokładnej wcześniejszej wartości Kelvina; domyślnie ustawia 4000 K.

## Naprawione błędy

- QML wywołuje `link(id)` / `unlink(id)` zamiast przekazywania obiektu QML.
- Kod sprawdza, czy ID i kontroler istnieją, i nie dereferencjonuje `undefined`.
- Dopasowuje klucze cache nawet przy rozbieżności typów ID.
- Przy `Unlink` wyszukuje discovery socket po **IP**, zamiast po ID.
- `PurgeCache` czyści także bieżącą mapę w pamięci.
- Korekta domyślnego portu kontrolera `55544 → 55444`.
- Brak wpisu IP cache nie powoduje próby tworzenia kontrolera z `undefined`.

Żarówki użytkownika użyte w testach: `colorc`, adresy `192.168.1.149`, `192.168.1.150`, `192.168.1.153`. Adresy IP **nie są wpisane na stałe w dodatku**.

## Testy i ograniczenia

GitHub Actions klonuje aktualny upstream, nakłada poprawki oraz weryfikuje składnię i zachowanie `Link/Unlink` z symulowanym API SignalRGB. Dodatkowe zadanie uruchamia PowerShell na Windows. Testy **nie zastępują rzeczywistego sprawdzenia w Twojej instalacji**.

Jeśli po `Link` nie działa synchronizacja, prześlij ostatnie komunikaty z konsoli, szczególnie zaczynające się od `[Bilina]`. Oryginalny dodatek obsługuje tylko kompatybilne urządzenia UDP, nie TCP-only.

## Źródła i prawa

Pochodzenie oryginału: [SignalRgb / Yeelight](https://gitlab.com/signalrgb/yeelight). Repozytorium upstream w pobranym archiwum nie zawiera osobnego pliku `LICENSE`. Z tego powodu to repozytorium publikuje **tylko własne skrypty nakładające poprawki i testy**, a nie kopię oryginalnego źródła. Instalator pobiera oryginał bezpośrednio od jego wydawcy. Nazwy SignalRGB/Yeelight należą do odpowiednich właścicieli. Projekt nie jest oficjalnym dodatkiem SignalRGB.
