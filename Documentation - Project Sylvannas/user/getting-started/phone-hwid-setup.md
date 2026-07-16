---
title: "Phone HWID Setup"
source: "https://docs.project-sylvanas.net/getting-started/phone-hwid-setup"
crawled: "2026-07-14"
---

# Phone HWID Setup

## Overview

The **Phone HWID System** adds an extra layer of flexibility to your account by linking your phone HWID directly to your account. This ensures that when you log in from a new or spoofed PC, your registered phone can verify and authorize the session automatically.

🔒 **Important:** This is a lock prevention system, not a lock removal tool. If your account becomes locked, you will still need to open a support ticket for a manual unlock.

## How HWID Lock Works

Your account is protected by an HWID check to prevent subscription sharing. If the loader sees a login from a new PC, spoofed PC, changed hardware, or another unexpected device, your account may lock until staff reviews it.

Phone HWID works as a physical verification step. If your registered phone is connected by USB during login, the loader can confirm it is still you and allow the login on a new or changed PC.

After the loader accepts your login, you can unplug the phone.

> **Note**
> 
> Phone HWID does not remove an existing lock. If you are already locked, open a ticket and ask for an HWID reset.

## Step 1: Plug In Your Phone

Before starting the authentication process, make sure your phone is **connected via USB** to your PC.

- Ensure your phone is **powered on**, unlocked if required by your OS, and visible to your PC.

## Step 2: Log In to the Loader

Launch your Loader and log in using your normal credentials.

## Step 3: Open the Authenticator

In the bottom-right corner of the loader, click the **Authenticator** button. This will open the Phone HWID setup interface.

## Step 4: Select Your Device

A list of connected devices will appear.

- Select your **phone** from the list.
- Click **Confirm** to pair it with your account.

Once confirmed, your phone's unique identifier will be linked to your Account. You can view your HWID Status at: [https://project-sylvanas.net/panel/shop/hwid](https://project-sylvanas.net/panel/shop/hwid)

## Step 5: Future Logins

From now on, whenever you log in from a **new or spoofed PC**, do the following:

1. Plug in your registered phone.
2. Log in as usual. The loader will automatically detect your verified device.
3. After login succeeds, you can unplug the phone.
4. Inject as usual.

✅ If your phone is not connected, a login from a new device will trigger a lock.

## Tips & Notes

- 🔌 Always keep your phone connected during login when using a new or changed PC.
- 🛑 This system prevents HWID lockouts, it does not remove existing locks.
- ✉️ If you get locked out, open a support ticket for help, the phone link will not bypass an existing lock.
- 📌 If you change phones, remove the old device from your account and register the new device as soon as possible.
- 📱 Phone HWID is not tied to a specific brand. Android and iPhone are supported, and any phone your PC can detect over USB should work.

## Troubleshooting

- If your phone does not appear in the device list, try:
  - Reconnecting the USB cable, using a different cable, or using a different USB port.
  - Enabling file transfer or debugging mode on the phone if your OS requires it.
  - Restarting the Loader and reconnecting the phone.
- If HWID status does not update on the web panel, try logging out and back into the panel, or reopen the Loader and re-confirm the device.

## Need Help?

If something still does not work, open a ticket on discord.

Every ticket must include your **Project Sylvanas web username** in the first message.

If you need an HWID reset, include:

- Your web username.
- A clear request for an HWID reset.
- A short reason for the reset request.

If your phone is not detected or phone HWID setup fails, include:

- Your web username.
- Your phone model and whether it is Android or iPhone.
- A screenshot of the loader/authenticator error, if any.
- What you already tried: different USB cable, different USB port, file transfer/debugging mode, restarting the loader, etc.
