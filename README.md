# C64 for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

Based on FPGA64 by Peter Wendrich with heavy later modifications by different people.

## Features
- C64 and C64GS modes.
- Disk read/write support (*.D64)
- Amost all cartrige formats (*.CRT)
- Direct file injection (*.PRG)
- Dual SID with several degree of mixing 6581/8580 from stereo to mono.
- Similar to 6581 and 8580 SID filters.
- OPL2 sound expander.
- 4 joysticks mode.
- UART connection to Internet.
- Loadable Kernal/C1541 ROMs.
- Parallel C1541 port for faster (~20x) loading time using DolphinDOS.
- Special reduced border mode for 16:9 display.

## Installation
Copy the *.rbf to the root of the SD card. Copy disks/carts to C64 folder.

## Usage

### Keyboard
* F2,F4,F6,F8,Left/Up keys automatically activate Shift key.
* F9 - arrow-up key.
* F10 - = key.
* F11 - restore key. Also special key in AR/FC carts.
* Alt - C= key.

![keyboard-mapping](https://github.com/mister-devel/C64_MiSTer/blob/master/keymap.gif)

### Loadable ROM
Alternative ROM can loaded from OSD: Hardware->Load System ROM.
Format is simple concatenation of BASIC + Kernal.rom + C1541.rom

To create the ROM in DOS or Windows, gather your files in one place and use the following command from the DOS prompt. 
The easiest place to acquire the ROM files is from the VICE distribution. BASIC and KERNAL are in the C64 directory,
and dos1541 is in the Drives directory.

`COPY BASIC + KERNAL + dos1541 MYOWN.ROM /B`

To use JiffyDOS or another alternative kernel, replace the filenames with the name of your ROM or BIN file.  (Note, you muse use the 1541-II ROM. The ROM for the original 1541 only covers half the drive ROM and does not work with emulators.)

`COPY /B BASIC.bin +JiffyDOS_C64.bin +JiffyDOS_1541-II.bin MYOWN.ROM`

To confirm you have the correct image, the BOOT.ROM created must be exactly 32768 or 49152(in case of 32KB C1541 ROM) bytes long. 

There are 2 loadable ROM sets are provided: **DolphinDOS v2.0** and **SpeedDOS v2.7**. Both ROMs support parallel Disk Port. DolphinDOS is fastest one.

### Autoload the cartridge
In OSD->Hardware page you can choose Boot Cartridge, so everytime core loaded, this cartridge will be loaded too.
