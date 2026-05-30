# Changelog

Wszystkie istotne zmiany w projekcie **WingetUpdater** będą dokumentowane w tym pliku.

Format jest oparty na zasadach [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), a numeracja wersji powinna być prowadzona zgodnie z [Semantic Versioning](https://semver.org/).

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

### Security
- Program wymusza uruchamianie przez `Start.bat`, aby ograniczyć przypadkowe uruchomienie głównego skryptu poza przewidzianym trybem.
- Launcher pokazuje treść licencji przed pierwszym uruchomieniem i zapisuje lokalny znacznik akceptacji.
- Kontekst diagnostyczny dla agenta AI zakłada bezpieczny research i brak zmian bez wyraźnego potwierdzenia użytkownika.

### Notes
- Repozytorium jest prywatne, więc release oraz pliki do pobrania są dostępne tylko dla osób z dostępem do repozytorium.
- Program jest przeznaczony dla systemu Windows.
- Program wymaga zainstalowanego Windows Package Managera (`winget`).
- Program powinien być uruchamiany przez `Start.bat`, a nie bezpośrednio przez `WingetUpdater.ps1`.

## Planowane w kolejnych wersjach

### Planned
- Dodanie automatycznego pakowania plików release do archiwum ZIP.
- Dodanie sum kontrolnych SHA256 dla publikowanych paczek.
- Dodanie workflow GitHub Actions do kontroli jakości i przygotowywania wydań.
- Rozbudowanie dokumentacji użytkownika w `README.md`.
- Dodanie sekcji znanych problemów oraz instrukcji diagnostycznych.
