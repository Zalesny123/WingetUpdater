# WingetUpdater by Zalesny123

**Wersja:** 1.0

Graficzne narzędzie (GUI) ułatwiające zarządzanie i aktualizację pakietów za pomocą menedżera `winget` w systemie Windows.

## Uruchamianie
- **`Start.bat`** - jedyny launcher programu.

`Start.bat` zawsze uruchamia program z uprawnieniami administratora. 
Najpierw sprawdza dostępność `CMD`, `PowerShell 5` i `PowerShell 7`.
Jeżeli dostępna jest tylko jedna opcja, uruchamia ją automatycznie. 
Jeżeli jest wybór, pyta użytkownika o preferowane środowisko (CMD / PS5 / PS7).

## Jak używać:
1. Program po starcie automatycznie sprawdza `winget upgrade`.
2. Domyślnie sprawdzane są również pakiety z nieznaną wersją przez flagę `--include-unknown` (można to wyłączyć w interfejsie).
3. Zaznacz **"Aktualizuj"** przy pakietach, które chcesz zaktualizować.
4. Zaznacz **"Pomijaj"** przy pakietach, których nie chcesz aktualizować.
5. Kliknij **"Zapisz pomijane"**, aby zachować wybór na przyszłość do pliku `skip-list.json`, albo od razu kliknij **"Aktualizuj zaznaczone"**.

## Naprawa pakietów Unknown:
- Wybierz terminal (PowerShell 7 admin, PowerShell 5 admin albo CMD admin).
- Wybierz agenta AI (Codex CLI albo Gemini CLI).
- Kliknij **"Napraw Unknown"**.
- Program otworzy terminal jako administrator w katalogu użytkownika i uruchomi wybrany CLI z wygenerowanym plikiem kontekstu diagnostycznego.

*(Kontekst wymusza na agencie AI wykonanie bezpiecznego researchu i zabrania wprowadzania zmian bez wyraźnego potwierdzenia użytkownika).*

## Lista pomijanych (Skip-list)
Program zapisuje pomijane pakiety w pliku `skip-list.json` obok skryptu. Przy następnym uruchomieniu te pakiety będą automatycznie oznaczane jako **"Pomijaj"**.

# Autor i Licencja
Program stworzony przez **Zalesny123**.
Kod udostępniany na warunkach licencji **MIT**. Szczegóły w pliku [LICENSE](LICENSE).
Copyright © 2026 Zalesny123
