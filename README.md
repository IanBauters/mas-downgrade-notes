# Final Cut Pro: version IDs and installing an archived App Store package

These are my notes for downgrading Final Cut Pro from the Mac App Store, and for installing an App Store `.pkg` that I keep in my own archive.

The method for getting an older version comes from **[nghlt/Downgrade-MAS-Applications](https://github.com/nghlt/Downgrade-MAS-Applications)**. Read and follow that guide first. These notes add three things:

1. A procedure to capture and save the App Store `.pkg` before it is automatically deleted.
2. A list of `appExtVrsId` values for Final Cut Pro.
3. A procedure to install a saved App Store `.pkg` later, without the App Store.

> You must own the app on your Apple ID. These notes do not help you get software that you did not buy.

---

## 1. Capture the App Store package

When downloading an application from the Mac App Store, the installer package is temporarily stored in the App Store agent's cache. After installation, macOS normally removes it.

To keep a copy, you need to capture it while the download is taking place.

### 1.1 Start a package watcher

Open Terminal and run:

```bash
CACHE_ROOT="$(getconf DARWIN_USER_CACHE_DIR)"

sudo env CACHE_ROOT="$CACHE_ROOT" sh -c '
base="${CACHE_ROOT}com.apple.appstoreagent/com.apple.appstore"
dest="/Users/Shared/FinalCut-Pro-10.6.10.pkg"

echo "Watching: $base"
echo "Destination: $dest"

while :; do
    f=$(find "$base" -type f -name "npw*.pkg" -print -quit 2>/dev/null)

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

The watcher searches the current user's App Store cache for a package named `npw*.pkg`. It copies the package to `/Users/Shared` and refreshes that copy as the download grows. Once the source size has remained unchanged for five consecutive checks, it considers the capture complete.

Keep this Terminal window open.

### 1.2 Download Final Cut Pro

In another Terminal window, or in the App Store, follow the original downgrade guide to request the desired version.

Start the download using the `appExtVrsId` for the version you want.

The watcher should detect the temporary `.pkg` automatically.

When the download finishes and the package size stabilises, the watcher stops. You should now have:

```text
/Users/Shared/FinalCut-Pro-10.6.10.pkg
```

The filename is just a local archive name. It does not affect the package itself.

### 1.3 Verify the captured package

Run:

```bash
pkgutil --check-signature "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
spctl --assess --type install -vvv "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
```

Check that the signature reports `signed by Apple for the App Store` and that Gatekeeper reports `accepted` with `source=Mac App Store`.

Do not assume that a successful capture means the package will install successfully on every macOS version. Keep the original package untouched in your archive.

---

## 2. Final Cut Pro version IDs (`appExtVrsId`)

Use one of these values for `appExtVrsId` in step 4 of the original guide.

| appExtVrsId | Version | Status |
|---|---|---|
| 860357778 | 10.6.10 | Confirmed (installed and tested) |
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

Some versions have more than one ID. Apple sometimes publishes a build again with the same version number.

To find the version of an ID that is not verified, download it with the original guide. Then type:

```bash
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

Pull requests or comments with corrections are welcome.

---

## 3. Install an archived App Store package

If you keep the `.pkg` for later use, you may find that you cannot install it with a double-click or with `sudo installer -pkg`.

In my case, both methods returned:

> The package FinalCut-Pro-10.6.10.pkg fails to meet Gatekeeper policy.

The package itself was not damaged. Its Apple signature was valid, and `spctl` accepted it. However, macOS's installer security service (`syspolicyd`) rejected it during its package revocation assessment.

The workaround is to expand the package and copy the application into `/Applications` manually. This bypasses the failing installer operation, not Gatekeeper's application signature checks.

### 3.1 Check the package

```bash
pkgutil --check-signature FinalCut-Pro-10.6.10.pkg
spctl -a -vv -t install FinalCut-Pro-10.6.10.pkg
```

The package should report `signed by Apple for the App Store` and `accepted` with `source=Mac App Store`.

### 3.2 Copy the package to /tmp

An administrator account cannot read the Desktop of a different user. Do this step in your usual account:

```bash
cp ~/Desktop/FinalCut-Pro-10.6.10.pkg /tmp/
```

Adjust the source path if your package is stored elsewhere.

### 3.3 Log in as an administrator

```bash
login <admin>
cd /tmp
```

### 3.4 Open the package and copy the app

```bash
pkgutil --expand-full /tmp/FinalCut-Pro-10.6.10.pkg /tmp/fcp
APP=$(find /tmp/fcp -maxdepth 5 -type d -name "Final Cut Pro.app" | head -1)
echo "$APP"
sudo ditto "$APP" "/Applications/Final Cut Pro.app"
```

For Final Cut Pro, the app is at:

```text
/tmp/fcp/FinalCut_AppStore.pkg/Payload/Applications/Final Cut Pro.app
```

If there is already a Final Cut Pro in `/Applications`, rename it first. If macOS asks if Terminal can change apps (App Management), click Allow.

### 3.5 Check the app and remove the temporary files

```bash
codesign --verify --deep --strict "/Applications/Final Cut Pro.app" && echo OK
sudo rm -rf /tmp/fcp /tmp/FinalCut-Pro-10.6.10.pkg
exit
```

### 3.6 Start the app

Open Final Cut Pro from your usual account. If it asks for an Apple ID, sign in with the Apple ID that bought it. The app uses this to get its purchase receipt.

---

## 4. Notes

- Turn SIP on again after you use the original guide.
- Keep the minimum macOS version next to each archived package. An older Final Cut Pro does not always start on a newer macOS, and the reverse.
- The manual extraction procedure in section 3 has been tested with Final Cut Pro 10.6.10. It should not be assumed to work with every App Store package.
- Keep the original `.pkg` in your archive. Do not modify its contents or discard it after extracting the application.
