# Guide: Building an iOS App from Windows via GitHub

This guide explains how to manage your Flutter project on **Windows** and use **GitHub Actions** to handle the heavy lifting of building the iOS version for you.

## 1. The Workflow Overview
Since you are on Windows, you can write 100% of the code, but you cannot compile the final iOS app file (`.ipa`) locally. Instead, we use GitHub's servers (which have Macs) to do the build for you.

---

## 2. Step-by-Step Instructions

### Step A: Make Changes on Windows
Work on your code in VS Code on your Windows PC as usual.
*   Test your changes on the **Chrome Web Browser** or an **Android Emulator/Phone**.
*   When you are happy with the changes, save all files.

### Step B: Push to GitHub
Open your Windows terminal (PowerShell) in the project folder and run:
```powershell
git add .
git commit -m "Description of your changes"
git push origin main
```

### Step C: Watch the Build on GitHub
1.  Open your repository on [GitHub.com](https://github.com/cloudanime/fif_quiz).
2.  Click the **Actions** tab at the top.
3.  You will see a new workflow run appearing (it will have a yellow spinning icon).
4.  Wait about 5-10 minutes for it to turn into a **Green Checkmark**.

### Step D: Download your iOS Files
1.  Click on the successful build name (e.g., "Description of your changes").
2.  Scroll down to the **Artifacts** section at the bottom.
3.  Click on **ios-release** to download the zip file.
    *   *Note: This zip contains the compiled app files. To install this on a real iPhone, you eventually need an Apple Developer account ($99/year), but for testing, this verifies your code is perfect.*

---

## 3. Syncing with your MacBook (Optional)
If you want to run the app directly from your MacBook:
1.  Open Terminal on the Mac.
2.  Go to the folder: `cd fif_quiz`
3.  Pull the latest changes from Windows:
    ```bash
    git pull origin main
    ```
4.  Run it:
    ```bash
    flutter run -d ios
    ```

---

## 4. Pro Tips for iOS
*   **Permissions**: If you add new features (like using the Camera), I must help you update the `Info.plist` file on Windows before you push to GitHub.
*   **App Icon**: Your app icon is set in `pubspec.yaml`. When you change the icon image on Windows and push, the GitHub build will automatically apply it to the iOS version too.
*   **Private Repo**: Keep your repository **Private** to ensure your Supabase database keys stay secure.
