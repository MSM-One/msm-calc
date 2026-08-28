import requests
import os

apk_path = r"c:\New Supabase\Calc\msm_calc\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"

url = "https://wztyczjrakjsoifwtdda.supabase.co/storage/v1/object/app-releases/msm_one_v1.0.2.apk"
anon_key = "sb_publishable_wg9tZMFH_PwptXm9nuB1tg_WzW23AkY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "x-upsert": "true",
    "Content-Type": "application/vnd.android.package-archive"
}

print(f"Uploading {apk_path} ({os.path.getsize(apk_path)} bytes) to Supabase Storage...")

with open(apk_path, "rb") as f:
    resp = requests.post(url, headers=headers, data=f)

print(f"Status Code: {resp.status_code}")
print(f"Response: {resp.text}")
