# SuperForgeRW

A robust RO2RW conversion module for Android 15-17 dynamic-super devices. Automates partition conversion and expansion (F2FS / EROFS / EXT4).

## Features
- **Standalone Statically Linked Utilities:** Includes the latest `e2fsprogs` and `f2fs-tools` completely statically linked. Resolves library dependency crashes across all environments (TWRP, OrangeFox, OS).
- **Modular Architecture:** Core logic is broken down into easily maintainable `.sh` modules inside `src/`.
- **Automated Filesystem Migration:** Seamlessly converts EXT4/EROFS to F2FS or expands existing RW images.

## Installation
Flash the release `.zip` archive via Magisk, KernelSU, or a custom recovery. 

*Private source tree. For development, modify scripts in `src/`.*

## Support
PR, Issues is closed. Discussions is open. 
