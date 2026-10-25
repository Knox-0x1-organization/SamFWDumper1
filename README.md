# SamFWDumper

SamFWDumper processes Samsung firmware in GitHub Actions, extracts selected partition images or system files, and uploads the results to GoFile or a GitHub Release. The firmware is downloaded by the Actions runner, so the user's device only needs to download the requested output. You do not need to install the extraction tools on your computer.

## Requirements

- A GitHub account and a fork of this repository.
- GitHub Actions enabled for your fork.
- A direct **HTTPS** firmware download link from [SamFW](https://samfw.com).

The workflows use GitHub-hosted runners and the `GITHUB_TOKEN` to create releases. No personal access token is required. For GitHub Releases, files above the workflow's configured 2 GiB upload threshold are sent to GoFile and linked in the release notes.

The targeted extractor also attaches a text report to its Actions run. In name-search mode, it lists every matching file or directory and its image path; the run fails if the name is not found.

For the targeted workflow, the runner reads the AP TAR from the SamFW ZIP using HTTP range requests and streams the selected partition image into extraction. It does not store the firmware ZIP on the runner or unpack unrelated firmware components.

## Run a workflow

1. Fork the repository using GitHub's **Fork** button.
2. In your fork, open **Actions**. If prompted, enable workflows.
3. Select a workflow, choose **Run workflow**, enter the HTTPS SamFW download link, and select the extraction and upload options.
4. Open the completed run. Download extracted files from the created release or use the GoFile link in its release notes.

The available workflows are:

| Workflow | Result |
| --- | --- |
| **1. Images Extractor** | Selected raw partition images, compressed as `.xz`. |
| **2. System Files Extractor** | Selected system file groups such as apps, libraries, configuration, and media. |
| **3. Special Targeted Extractor** | Files or directories found by exact name anywhere in the system image. |
| **4. Full Firmware Fetcher** | The original downloaded firmware package. |

### Find a system file or directory by name

In **3. Special Targeted Extractor**, enter the exact basename in **Search name**. The workflow searches recursively across the system image, extracts every matching file or directory, and keeps each match's path under the output's `system/` folder. For example, entering `floating_feature` finds it even if its location differs between firmware builds. A matching directory is extracted with its contents. The run reports an error if there are no matches. Enter only the name, not a path; names may contain letters, numbers, dots, underscores, plus signs, and hyphens.

### Get a direct SamFW link

1. Find the device model, region/CSC, and firmware version on [SamFW](https://samfw.com).
2. Select **Download SamFW Server** and wait for the direct **Download** button.
3. Copy the button's link address without starting the download.
4. Paste the HTTPS link into the workflow's firmware URL field.

## Extraction details

The image extractor supports `boot`, `dtbo`, `init_boot`, `odm`, `odm_dlkm`, `product`, `recovery`, `system`, `system_dlkm`, `system_ext`, `vbmeta`, `vbmeta_system`, `vendor`, `vendor_boot`, and `vendor_dlkm`. A/B image names such as `system_a` and `system_b` are preserved.

System-file extraction can select apps, binaries, camera data, configuration, 32-bit and 64-bit libraries, media, privileged apps, Samsung AI Vision files, build properties, framework overlays, PIT files, and wallpaper resources. Availability depends on the firmware package and partition layout.

Workflows accept HTTPS download links and use normal TLS certificate validation. The output compression setting trades processing time for file size. Firmware extraction can take several minutes and use substantial runner storage.

## Troubleshooting

- **The workflow is missing:** Enable GitHub Actions in the fork and check that the workflow files are present on its default branch.
- **The firmware download fails:** Confirm that the link is a direct HTTPS download link and has not expired.
- **A targeted search finds no matches:** Check the exact basename and firmware's system image. The run log and extraction report show the search result.
- **Release upload fails or files are too large:** Choose GoFile as the destination. GitHub Releases have an individual asset size limit.
- **A tool is missing:** Review the workflow log for the first failing command and include that section in an issue report.

## License and redistribution

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). Review the license before use or redistribution. The repository's current distribution policy requires distribution through GitHub's fork mechanism; contact the copyright holder about commercial permissions.

The repository bundles third-party utilities under their respective licenses. See [Tools used](#tools-used) and each upstream project for applicable notices and source terms.

## Tools used

- [nmeum/android-tools](https://github.com/nmeum/android-tools) (Apache-2.0): `simg2img`, `img2simg`, `ext2simg`, `append2simg`.
- [LonelyFool/lpunpack_and_lpmake](https://github.com/LonelyFool/lpunpack_and_lpmake) (Apache-2.0): `lpunpack`, `lpdump`, `lpmake`.
- [sekaiacg/erofs-utils](https://github.com/sekaiacg/erofs-utils): EROFS utilities.
- [AOSP Verified Boot tools](https://android.googlesource.com/platform/external/avb) (Apache-2.0): `avbtool`.
- [AOSP e2fsprogs](https://android.googlesource.com/platform/external/e2fsprogs) (Apache-2.0): `e2fsdroid`, `mke2fs.android`.
- [AOSP f2fs-tools](https://android.googlesource.com/platform/external/f2fs-tools) (Apache-2.0): `make_f2fs`, `sload_f2fs`.
- [AOSP mkbootimg](https://android.googlesource.com/platform/system/tools/mkbootimg): boot image utilities.
- [AOSP libufdt](https://android.googlesource.com/platform/system/libufdt) (Apache-2.0): `mkdtboimg`.
- [e2fsprogs](https://github.com/tytso/e2fsprogs): `debugfs`.
- [XZ Utils](https://github.com/tukaani-project/xz): XZ compression.
- [LZ4](https://github.com/lz4/lz4): LZ4 compression.
- [GoFile API](https://gofile.io/api): optional upload destination.

Check the bundled third-party components for their full license and attribution terms.

## Credits

Samsung firmware is sourced through [SamFW](https://samfw.com). Thanks to project contributors [Ravindu Deshan](https://github.com/ravindu644), [DevCatowa](https://github.com/DevCat3), [QOS3](https://github.com/QOS3), and [MRX7014](https://github.com/mrx7014).

Copyright © 2026 Xiatsuma.
