# Final Cut Pro: version IDs and archived App Store packages

These are my notes for downloading older versions of Final Cut Pro from the Mac App Store and keeping copies of the installers.

The method for downloading older versions comes from **[nghlt/Downgrade-MAS-Applications](https://github.com/nghlt/Downgrade-MAS-Applications)**. Read and follow that guide first.

This repository adds three things:

1. A list of `appExtVrsId` values for Final Cut Pro.
2. **Keeper**, a small Mac app that saves the App Store package during the download, checks it, archives it and installs the app.
3. The manual method that Keeper replaces, for reference.

> You must own Final Cut Pro on your Apple ID. These notes do not provide access to software that you have not purchased.

---

## 1. Final Cut Pro version IDs (`appExtVrsId`)

Use one of these values for `appExtVrsId` in step 4 of the original guide.

| appExtVrsId | Version | Status |
|---|---|---|
| 858759812 | 10.6.8 | Confirmed (installed with Keeper) |
| 860357778 | 10.6.10 | Confirmed (installed with Keeper) |
| 868934312 | 11.0 | Confirmed |
| 869630074 | 11.0 | Confirmed |
| 870244110 | 11.0 | Confirmed |
| 871732983 | 11.0.1 | Confirmed |
| 872058532 | 11.0.1 | Confirmed |
| 872452762 | 11.1 | Confirmed |
| 873376670 | 11.1 | Confirmed |
| 874753139 | 11.1.1 | Confirmed |
| 877853662 | 11.2 | Confirmed |
| 878609324 | 12.0 | Confirmed |
| 881360665 | Unknown | Not verified |
| 883683783 | Unknown | Not verified |
| 883948682 | Unknown | Not verified |
| 885048303 | Unknown | Not verified |
| 885086868 | 12.3 | Confirmed |
| 890018965 | 12.4 | Confirmed |
| 891612528 | 12.4 | Confirmed |
| 892719956 | 13.0 | Confirmed |
| 893630008 | 13.0 | Confirmed |

Some versions have more than one ID. Apple sometimes releases the same version number more than once.

To identify an ID that is not verified, download it with the original guide. Keeper shows the version after the download. Without Keeper, run:

```bash
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

Pull requests and comments with corrections are welcome.

---

## 2. Normal App Store installation

For most versions, the normal App Store installation works. Follow the original guide to request the version that you want, and let the App Store install Final Cut Pro.

The App Store deletes the installer package after the installation. If you want to keep a copy, use Keeper (section 3) during the download.

**Final Cut Pro 10.6.8 and 10.6.10 are exceptions.** The App Store downloaded the package, but macOS refused to install it, with this error:

> The package FinalCut-Pro-10.6.10.pkg fails to meet Gatekeeper policy.

The packages had a valid Apple signature and Gatekeeper accepted them, but the installer service refused them. The system log showed `Denying revoked package`. `sudo installer -pkg` gives the same result. The solution is to save the package before the App Store deletes it, and copy the app into `/Applications` yourself. Keeper does this for you.

---

## 3. Keeper

Keeper is a native Mac app (SwiftUI, macOS 13 or later). You still use Proxyman and Frida to request the old version. Keeper does everything after that:

1. **Capture.** Keeper watches the App Store download folder. When a download starts, it keeps the package, so the package stays when the App Store deletes its copy.
2. **Check.** Keeper checks the package signature (`pkgutil --check-signature`) and Gatekeeper (`spctl`). Then it opens the package and reads the name, version and minimum macOS version of the app.
3. **Archive.** Keeper saves the package in your archive folder as `<App> <version>.pkg`, for example `Final Cut Pro 10.6.10.pkg`, with a `.json` file that contains the version details.
4. **Install.** Keeper copies the app to `/Applications`. macOS asks for an administrator name and password. If the app is already there, Keeper renames the old one to `<App> <old version>.app`. Then Keeper checks the code signature.

You can also drop an archived `.pkg` on the Keeper window to check and install it later.

### 3.1 Build Keeper

You need the Command Line Tools (`xcode-select --install`). You do not need Xcode or an administrator account.

```bash
git clone https://github.com/IanBauters/mas-downgrade-notes.git
cd mas-downgrade-notes/Keeper
./build.sh
```

The app is in `Keeper/build/Keeper.app`. Drag it to `/Applications` in Finder.

> If the build fails with "this SDK is not supported by the compiler", your Command Line Tools are partly updated. `build.sh` tries every installed SDK. If none works, update the Command Line Tools with `softwareupdate`.

### 3.2 Use Keeper

1. Open Keeper.
2. Turn on **Always watch as administrator** if your account cannot read the App Store download folder. Keeper also does this by itself when it finds a folder that it cannot read.
3. Click **Start watching**. Type the administrator name and password if macOS asks.
4. Request the version in the App Store with Proxyman and Frida, as in the original guide.
5. Wait. Keeper shows the size of the download. When the App Store finishes (or the installation fails), Keeper saves the package, checks it and archives it.
6. Click **Install <App> <version>** and type an administrator name and password.
7. Open the app. If it asks for an Apple ID, sign in with the Apple ID that purchased it. The app uses this to get its purchase receipt.

### 3.3 Notes on Keeper

- The App Store gives each download a random name (for example `ojw2124424035809939862.pkg`) in a new subfolder of `$(getconf DARWIN_USER_CACHE_DIR)com.apple.appstoreagent/com.apple.appstore`. Keeper takes any new `.pkg` in that folder.
- If macOS says that Keeper cannot change apps, allow Keeper in System Settings > Privacy & Security > App Management.
- The default archive folder is `~/Documents/App Store Packages`. Click **Change…** to use a different folder, for example on a NAS.
- Temporary files are in `~/Library/Caches/Keeper`. Keeper deletes the extracted app after the installation and when it starts.
- The watcher stops after 2 hours if no download starts.

---

## 4. Manual method

<details>
<summary>The Terminal steps that Keeper replaces</summary>

### 4.1 Save the package during the download

You need an administrator account for this step.

> **If your account is not an administrator**
>
> 1. In your usual account, run `getconf DARWIN_USER_CACHE_DIR` and write down the result.
> 2. Log in to an administrator account with `login <admin>`.
> 3. In the script below, change the first line to `CACHE_ROOT="<the result from step 1>"`.

The App Store stores temporary installer packages in its cache and deletes them after the installation. Copy the package while the download is in progress. The file name is random, so the script takes any `.pkg` in the folder.

```bash
CACHE_ROOT="$(getconf DARWIN_USER_CACHE_DIR)"

sudo env CACHE_ROOT="$CACHE_ROOT" sh -c '
base="${CACHE_ROOT}com.apple.appstoreagent/com.apple.appstore"
dest="/Users/Shared/FinalCut-Pro-10.6.10.pkg"

echo "Watching: $base"
echo "Destination: $dest"

while :; do
    f=$(find "$base" -type f -name "*.pkg" -print -quit 2>/dev/null)

    if [ -n "$f" ]; then
        echo "Found package: $f"

        previous=0
        stable=0

        while [ -f "$f" ]; do
            size=$(stat -f%z "$f" 2>/dev/null || echo 0)

            if [ "$size" -gt 0 ]; then
                cp "$f" "$dest.tmp" 2>/dev/null && mv -f "$dest.tmp" "$dest"

                if [ "$size" -eq "$previous" ]; then
                    stable=$((stable + 1))
                else
                    stable=0
                fi

                previous=$size

                if [ "$stable" -ge 5 ]; then
                    echo "Package size is stable."
                    ls -lh "$dest"
                    exit 0
                fi
            fi

            sleep 1
        done

        echo "Source disappeared. Looking for another package."
    fi

    sleep 0.2
done
'
```

Keep this Terminal window open, then request the version with the original guide (for 10.6.10, `appExtVrsId` is `860357778`).

### 4.2 Check the package

```bash
pkgutil --check-signature "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
spctl --assess --type install -vvv "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
```

The expected results are `signed by Apple for the App Store`, `accepted` and `source=Mac App Store`. These checks do not guarantee that the installer will accept the package.

### 4.3 Extract the application and copy it to /Applications

> **If your account is not an administrator**
>
> 1. Copy the package to `/tmp`: `cp /Users/Shared/FinalCut-Pro-10.6.10.pkg /tmp/`
> 2. Log in to an administrator account: `login <admin>`
> 3. In the commands below, change `/Users/Shared` to `/tmp`.
>
> Type `exit` after section 4.5 to go back to your usual account.

```bash
pkgutil --expand-full /Users/Shared/FinalCut-Pro-10.6.10.pkg /tmp/fcp
APP=$(find /tmp/fcp -maxdepth 5 -type d -name "Final Cut Pro.app" | head -1)
echo "$APP"
sudo ditto "$APP" "/Applications/Final Cut Pro.app"
```

The application is at `/tmp/fcp/FinalCut_AppStore.pkg/Payload/Applications/Final Cut Pro.app`.

If Final Cut Pro is already in `/Applications`, rename it before you copy the new one. If macOS asks for permission to let Terminal change applications, click Allow.

### 4.4 Verify the application

```bash
codesign --verify --deep --strict "/Applications/Final Cut Pro.app" && echo OK
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

The first command should report `OK`. The second should report `10.6.10`.

### 4.5 Remove temporary files

```bash
sudo rm -rf /tmp/fcp
```

If you copied the package to `/tmp`, also remove `/tmp/FinalCut-Pro-10.6.10.pkg`. This does not delete the package in `/Users/Shared`. Keep that copy for your archive.

</details>

---

## 5. Notes

- Turn SIP on again after you use the original downgrade guide.
- Keep the minimum macOS version with each archived package. Keeper writes it in the `.json` file.
- An older version of Final Cut Pro may not run on a newer version of macOS. A newer version may also require a newer version of macOS.
- The manual installation was only needed for Final Cut Pro 10.6.8 and 10.6.10. I have not tested it with every App Store package.
- Keep an untouched copy of each archived `.pkg`.
