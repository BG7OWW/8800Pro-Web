# Changelog

## 2026-06-17

- Added the 8800Pro Bluetooth frequency-write path with paired frame ACK handling.
- Paused Bluetooth boot-image writing in the UI and protocol layer. When connected by Bluetooth, the boot-image write action now reports that the feature is still in development and asks the user to use the programming cable.
- Kept USB boot-image writing on the 8800Pro A5 boot-image protocol.
- Added write-before-review diff UI for radio data changes.
- Kept separate builds for GitHub Pages and the self-hosted server; the server build preserves the备案号 sidebar/footer.
