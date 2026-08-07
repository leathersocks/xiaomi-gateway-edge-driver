# Changelog

## v1.2.6f-final - 2026-08-07

- Clean distribution build based on verified v1.2.6f.
- Removed archive and all historical setup wrappers.
- Removed V2 fallback and duplicate diagnostics source.
- Removed development templates.
- Pre-populated the final five custom capability IDs in the Device Profile.
- Pre-populated `src/generated_capabilities.lua`.
- Direct `smartthings edge:drivers:package . --install` is now supported without setup.
- Kept only five capability definitions, five presentations, and ten EN/KO translations.
- Added optional `sync-ui.ps1` for re-applying capability names, translations, and presentations.
- Runtime and miIO networking logic unchanged from v1.2.6f.
