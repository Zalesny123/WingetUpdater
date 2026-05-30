# Changelog

## [1.0.0] - 2026-05-30

### Added
- Pierwsza stabilna wersja projektu **WingetUpdater**.
- Graficzny interfejs użytkownika do sprawdzania i aktualizowania pakietów przez `winget`.
- Automatyczne sprawdzanie dostępnych aktualizacji po uruchomieniu programu.
- Obsługa pakietów z nieznaną wersją przez opcję `--include-unknown`.
- Możliwość wybierania konkretnych pakietów do aktualizacji.
- Możliwość pomijania wybranych pakietów.
- Trwała lista pomijanych pakietów zapisywana w pliku `skip-list.json`.
- Launcher `Start.bat` jako jedyny zalecany sposób uruchamiania programu.
- Automatyczne wykrywanie dostępnego środowiska uruchomieniowego: CMD, Windows PowerShell 5.1 lub PowerShell 7+.
- Obsługa uruchamiania programu z uprawnieniami administratora.
- Obsługa trybu naprawy pakietów z nieznaną wersją przez funkcję „Napraw Unknown”.
- Generowanie kontekstu diagnostycznego dla agenta AI przy naprawie pakietów Unknown.
- Obsługa licencji MIT.
- Inne funkcje, wyżej niewymienione a obecne w GUI programu.

### Notes
- Program wymusza uruchamianie przez `Start.bat`, aby ograniczyć przypadkowe uruchomienie głównego skryptu poza przewidzianym trybem.
- Launcher pokazuje treść licencji przed pierwszym uruchomieniem i zapisuje lokalny znacznik akceptacji.
- Kontekst diagnostyczny dla agenta AI zakłada bezpieczny research i brak zmian bez wyraźnego potwierdzenia użytkownika.
- Program jest przeznaczony dla systemu Windows.
- Program wymaga zainstalowanego Windows Package Managera (`winget`).
