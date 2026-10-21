#!/usr/bin/env python3
import json
import subprocess
import os
import sys

def main():
    if not os.path.exists("apps.json"):
        print("No apps.json found, skipping custom apps.")
        return

    with open("apps.json", "r") as f:
        apps = json.load(f)

    os.makedirs("sites", exist_ok=True)
    installed_apps = ["frappe"]

    for app in apps:
        url = app.get("url")
        branch = app.get("branch", "main")
        name = app.get("name") or url.rstrip("/").split("/")[-1].replace(".git", "")
        target = f"apps/{name}"

        print(f"\n=======================================================")
        print(f"Installing {name} from {url} (branch: {branch})")
        print(f"=======================================================")

        if not os.path.exists(target):
            subprocess.run(["git", "clone", "--depth", "1", "-b", branch, url, target], check=True)

        print(f"Installing Python requirements for {name}...")
        subprocess.run(["./env/bin/pip", "install", "--no-cache-dir", "-e", target], check=True)

        installed_apps.append(name)

    # Save apps list to sites/apps.txt and keep a backup in bench root
    apps_txt_content = "\n".join(installed_apps) + "\n"
    with open("sites/apps.txt", "w") as f:
        f.write(apps_txt_content)
    with open("apps_txt_dist", "w") as f:
        f.write(apps_txt_content)

    print(f"\nSuccessfully configured apps: {', '.join(installed_apps)}")

if __name__ == "__main__":
    main()
