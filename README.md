# Final Cut Pro: version IDs and installing an archived App Store package

These are my notes for downgrading Final Cut Pro from the Mac App Store, and for installing an App Store `.pkg` that I keep in my own archive.

The method for getting an older version comes from **[nghlt/Downgrade-MAS-Applications](https://github.com/nghlt/Downgrade-MAS-Applications)**. Read and follow that guide first. These notes add two things:

1. A list of `appExtVrsId` values for Final Cut Pro.
2. A procedure to install a saved App Store `.pkg` later, without the App Store.

> You must own the app on your Apple ID. These notes do not help you get software that you did not buy.

---

## 1. Final Cut Pro version IDs (`appExtVrsId`)

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

```
defaults read "/Applications/Final Cut Pro.app/Contents/Info.plist" CFBundleShortVersionString
```

Pull requests or comments with corrections are welcome.

---

## 2. Install an archived App Store package

If you keep the `.pkg` for later use, you cannot install it with a double-click. You cannot install it with `sudo installer -pkg` either. The two methods give this error:

> The package FinalCut-Pro-10.6.10.pkg fails to meet Gatekeeper policy.

The package is not damaged. macOS lets only the App Store install App Store packages. The install log shows:

```
Failed install preflight: ... fails to meet Gatekeeper policy ...
PKInstallPackageIdentifier=com.apple.pkg.FinalCut_AppStore
NSUnderlyingError=... {Error Domain=SPErrorDomain Code=3}
```

The solution: open the package and copy the app into `/Applications` manually.

### 2.1 Check the package

```
pkgutil --check-signature FinalCut-Pro-10.6.10.pkg
spctl -a -vv -t install FinalCut-Pro-10.6.10.pkg
```

The package is good if `pkgutil` shows `signed by Apple for the App Store` and `spctl` shows `accepted` with `source=Mac App Store`.

### 2.2 Copy the package to /tmp

An administrator account cannot read the Desktop of a different user. Do this step in your usual account:

```
cp ~/Desktop/FinalCut-Pro-10.6.10.pkg /tmp/
```

### 2.3 Log in as an administrator

```
login <admin>
cd /tmp
```

### 2.4 Open the package and copy the app

```
pkgutil --expand-full /tmp/FinalCut-Pro-10.6.10.pkg /tmp/fcp
APP=$(find /tmp/fcp -maxdepth 5 -type d -name "Final Cut Pro.app" | head -1)
echo "$APP"
sudo ditto "$APP" "/Applications/Final Cut Pro.app"
```

For Final Cut Pro, the app is at `/tmp/fcp/FinalCut_AppStore.pkg/Payload/Applications/Final Cut Pro.app`.

If there is already a Final Cut Pro in `/Applications`, rename it first. If macOS asks if Terminal can change apps (App Management), click Allow.

### 2.5 Check the app and remove the temporary files

```
codesign --verify --deep --strict "/Applications/Final Cut Pro.app" && echo OK
sudo rm -rf /tmp/fcp /tmp/FinalCut-Pro-10.6.10.pkg
exit
```

### 2.6 Start the app

Open Final Cut Pro from your usual account. If it asks for an Apple ID, sign in with the Apple ID that bought it. The app uses this to get its purchase receipt.

---

## 3. Notes

- Turn SIP on again after you use the original guide.
- Keep the minimum macOS version next to each archived package. An older Final Cut Pro does not always start on a newer macOS, and the reverse.
- The procedure in section 2 works for other App Store packages too. Change the package and app names.
