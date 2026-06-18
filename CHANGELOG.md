# Changelog

## 2026-06-18

- Switched Web Bluetooth read/write to the official APK-style `0x80` native block protocol with full sequential writes, and exposed the previous `0x40` stream writer as a separate fast-write button.
- Added VFO scramble and PTT-ID controls based on fields already present in the 8800Pro memory map.
- Fixed the repeater library layout so the expanded database no longer squeezes the channel editor.
- Added the HamCQ repeater database to the web app as a lazy-loaded static data package.
- Redesigned the channel-page repeater library into a full-width region/province/city browser with search, incremental loading, and one-click write preview.

## 2026-06-17

- Added the 8800Pro Bluetooth frequency-write path with paired frame ACK handling.
- Paused Bluetooth boot-image writing in the UI and protocol layer. When connected by Bluetooth, the boot-image write action now reports that the feature is still in development and asks the user to use the programming cable.
- Kept USB boot-image writing on the 8800Pro A5 boot-image protocol.
- Added write-before-review diff UI for radio data changes.
- Kept separate builds for GitHub Pages and the self-hosted server; the server build preserves the备案号 sidebar/footer.
