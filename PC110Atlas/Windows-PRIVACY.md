# PC110 Atlas for Windows: privacy policy

Effective September 14, 2026.

PC110 Atlas for Windows processes imported files locally. It does not send
personal information to the developer and does not include advertising,
analytics, tracking, an app account system, or in-app purchases.

## Imported files and guest content

The app can read firmware and disk images that you explicitly select with the
Windows file picker. Imported disk images may contain personal information,
including documents, contacts, or other content from the guest computer.
The app copies selected files to its on-device data directory and uses those
copies for emulation. The source files you select are not modified.

Imported files and guest content are not uploaded by PC110 Atlas. The app does
not independently scan your computer for firmware, documents, or other media.
Only import files you are entitled to use, and consider who can access your
Windows account before importing sensitive guest data.

## Local emulation, display, and audio

The Windows QEMU backend runs as a local child process. Display frames,
keyboard and pointer input, and guest audio travel through private local
process pipes. Guest audio is played through the computer's selected output
device. The app does not record the microphone or send guest audio to a server.
Guest networking is disabled. The included demonstration uses open-source
firmware and an original demo disk, separately from imported personal media.

## External links

The built-in hardware atlas does not require an internet connection. Choosing
a source, video, support, or other external link opens that destination in an
external application. The destination may process information under its own
privacy policy. You choose whether to send information when contacting support.

## Storage and deletion

Imported copies remain on your computer until you replace or delete them or
remove the relevant app data. The original files and any separate backups
remain where you saved them. Do not rely on uninstalling the app to remove
original files or copies outside its managed package storage.

Your Windows backup, synchronization, and device-management settings may apply
to files on the computer independently of PC110 Atlas. The app itself does not
provide cloud backup or send imported media to a backup service.

## Children

PC110 Atlas does not collect personal information from children or other users
for the developer. Imported files are processed locally as described above.

## Changes and contact

Material changes will be reflected in this policy and its effective date.
For privacy or support questions, use the
[project issue tracker](https://github.com/ahmadexp/PC110_MiSTer/issues).
That tracker is public. Do not post private disk images, passwords, or other
sensitive information in an issue.
