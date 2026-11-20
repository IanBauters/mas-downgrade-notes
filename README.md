# Final Cut Pro: version IDs and archived App Store packages

These are my notes for downloading older versions of Final Cut Pro from the Mac App Store and keeping copies of the installers.

The method for downloading older versions comes from **[nghlt/Downgrade-MAS-Applications](https://github.com/nghlt/Downgrade-MAS-Applications)**. Read and follow that guide first.

These notes add two things:

1. A list of `appExtVrsId` values for Final Cut Pro.
2. A procedure to save and install an archived App Store package.

> You must own Final Cut Pro on your Apple ID. These notes do not provide access to software that you have not purchased.

**Important:** I used the normal App Store installation process for all tested versions except 10.6.10. Final Cut Pro 10.6.10 required a manual workaround. The additional steps in section 3 apply only to that version. Do not use them for other versions unless you have the same installation problem.

---

## 1. Final Cut Pro version IDs (`appExtVrsId`)

Use one of these values for `appExtVrsId` in step 4 of the original guide.

| appExtVrsId | Version | Status |
|---|---|---|
| 860357778 | 10.6.10 | Confirmed (manual installation) |
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

To identify an ID that is not verified, download it with the original guide. Then run:

```bash
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

Pull requests and comments with corrections are welcome.

---

## 2. Normal App Store installation

For all tested versions except 10.6.10, I used the normal App Store installation process.

Follow the original guide to request the version that you want. When the download is complete, let the App Store install Final Cut Pro.

You do not need the manual installation procedure in section 3 if the App Store installation works.

---

## 3. Final Cut Pro 10.6.10: save and install the package manually

**This procedure was only needed for Final Cut Pro 10.6.10.**

The App Store downloaded the package, but macOS refused to install it. The package had a valid Apple signature. Gatekeeper also accepted it. However, the macOS installer service reported that the package did not meet Gatekeeper policy.

The system log showed:

```text
Denying revoked package
```

I could not establish why macOS rejected this package. The workaround was to save the package before the App Store deleted it, then copy the application into `/Applications` manually.

### 3.1 Save the package during the download

**You need an administrator account for this step.**

> **If your account is not an administrator**
>
> 1. In your usual account, run `getconf DARWIN_USER_CACHE_DIR` and write down the result.
> 2. Log in to an administrator account with `login <admin>`.
> 3. In the script below, change the first line to `CACHE_ROOT="<the result from step 1>"`.

The App Store stores temporary installer packages in its cache. It normally deletes these files after installation.

You must copy the package while the download is in progress.

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

Keep this Terminal window open.

### 3.2 Download Final Cut Pro 10.6.10

Use the original guide to request Final Cut Pro 10.6.10.

The `appExtVrsId` is:

```text
860357778
```

The script searches the App Store cache for the temporary package. It copies the package to:

```text
/Users/Shared/FinalCut-Pro-10.6.10.pkg
```

When the download is complete, the script checks that the file size has stopped changing. It then stops.

### 3.3 Check the package

Run:

```bash
pkgutil --check-signature "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
spctl --assess --type install -vvv "/Users/Shared/FinalCut-Pro-10.6.10.pkg"
```

The expected results are:

- `signed by Apple for the App Store`
- `accepted`
- `source=Mac App Store`

These checks confirm the package signature and its Gatekeeper assessment. They do not guarantee that the installer will accept the package.

### 3.4 Extract the application and copy it to /Applications

> **If your account is not an administrator**
>
> `sudo` does not work in your account. Do these steps first:
>
> 1. Copy the package to `/tmp`:
>    ```bash
>    cp /Users/Shared/FinalCut-Pro-10.6.10.pkg /tmp/
>    ```
> 2. Log in to an administrator account:
>    ```bash
>    login <admin>
>    ```
> 3. In the commands below, change `/Users/Shared` to `/tmp`.
>
> Type `exit` after section 3.6 to go back to your usual account.

```bash
pkgutil --expand-full /Users/Shared/FinalCut-Pro-10.6.10.pkg /tmp/fcp
APP=$(find /tmp/fcp -maxdepth 5 -type d -name "Final Cut Pro.app" | head -1)
echo "$APP"
sudo ditto "$APP" "/Applications/Final Cut Pro.app"
```

The application is inside:

```text
/tmp/fcp/FinalCut_AppStore.pkg/Payload/Applications/Final Cut Pro.app
```

If Final Cut Pro is already in `/Applications`, rename the existing application before you copy the new one.

If macOS asks for permission to let Terminal change applications, click Allow.

### 3.5 Verify the application

Run:

```bash
codesign --verify --deep --strict "/Applications/Final Cut Pro.app" && echo OK
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

The first command should report `OK`. The second should report `10.6.10`.

### 3.6 Remove temporary files

After you have verified the application:

```bash
sudo rm -rf /tmp/fcp
```

If you copied the package to `/tmp`, also remove `/tmp/FinalCut-Pro-10.6.10.pkg`.

This does not delete the package in `/Users/Shared`. Keep that copy for your archive.

Open Final Cut Pro.

If it asks for an Apple ID, sign in with the Apple ID that purchased the application. The app uses this to access its purchase receipt.

---

## 4. Notes

- Turn SIP on again after you use the original downgrade guide.
- Keep the minimum macOS version with each archived package.
- An older version of Final Cut Pro may not run on a newer version of macOS. A newer version may also require a newer version of macOS.
- The manual workaround in section 3 was tested with Final Cut Pro 10.6.10. I have not tested it with every App Store package.
- Keep an untouched copy of each archived `.pkg`.
- The normal App Store installation process worked for the other tested Final Cut Pro versions. Section 3 documents an exception, not the standard installation method.
