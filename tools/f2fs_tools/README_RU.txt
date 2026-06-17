Сюда можно положить verified Android arm64/arm32 f2fs-tools, если recovery их не содержит.

Имена, которые скрипт ищет автоматически:
  arm64/make_f2fs или arm64/mkfs.f2fs
  arm64/sload_f2fs или arm64/sload.f2fs
  arm64/resize.f2fs
  arm64/fsck.f2fs

Для arm32 — те же имена в arm32/.

v4.4.3 сам НЕ содержит новые бинарники f2fs-tools, потому что нельзя безопасно подмешивать непроверенные бинарники. Если ты дашь verified static Android arm64 binaries, их можно вставить в ZIP.
