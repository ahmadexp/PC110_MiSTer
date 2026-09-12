# PC 110 Privacy Policy

Effective date: September 6, 2026

PC 110 does not collect, transmit, sell, or share personal data. It does not contain advertising SDKs, analytics SDKs, tracking technology, user accounts, or in-app purchases.

## Files You Import

The iPhone, iPad, Mac, native Vision Pro, and Android apps can import firmware, disk-image, and supported customization files that you select through the operating system's document picker. Those files are validated and copied into the app's private on-device storage for emulation or display. They are not uploaded by PC 110. Replaced files receive a local backup where that feature is available. Android cloud backup is disabled for the app so imported media is not placed in the app's Android backup set. The Apple TV app does not import or store emulator media.

## Native Vision Pro App

Emulation and guest audio run locally on Vision Pro. The app's spatial windows share one on-device session and do not stream imported media to another device. The app does not request camera, microphone, eye-tracking, hand-tracking, or room-mapping data. Standard gaze and hand interactions are handled by the operating system's user-interface framework.

## Apple Watch Companion

When you use the Apple Watch companion, the paired iPhone and Apple Watch exchange emulator status, compressed display previews, downsampled guest audio, and remote-input commands through Apple's WatchConnectivity service. These paired-device messages may reflect content visible or audible inside the guest operating system, but PC 110 does not send them to the developer or to an application server. Audio packets are played transiently and are not saved on the Watch. Firmware and disk-image files remain on the iPhone and are not copied to the Watch.

## Network Access and External Links

The app does not make an automatic internet request when it launches or while you browse its built-in content. Paired-device WatchConnectivity traffic is described above. If you choose a link to a source repository, legal notice, privacy policy, or other external resource, the operating system opens that destination. The destination's operator may process data under its own privacy policy.

## Data Retention and Deletion

Imported files remain on your device until you replace them, remove the app, or erase its data. Because PC 110 does not receive your data, there is no server-side account or personal record to delete.

## Children

PC 110 does not knowingly collect personal data from anyone, including children.

## Changes

Material changes to this policy will be reflected on this page with a new effective date.

## Contact

For privacy or support questions, open an issue at <https://github.com/ahmadexp/PC110_MiSTer/issues>.

## Native visionOS bundled demo

The native visionOS edition includes an original boot demonstration and
open-source SeaBIOS firmware. The demo runs locally, requires no download or
account, and copies its disposable disk to a dedicated app-support directory.
It does not read imported guest disks, access the network, or collect analytics.
Its source and firmware license materials can be exported from Credits using
the system share sheet, only when the user chooses to share them.
