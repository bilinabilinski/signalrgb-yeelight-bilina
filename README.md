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
