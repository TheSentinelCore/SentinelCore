---
title: "How to Use PS with Private Servers"
source: "https://docs.project-sylvanas.net/dev/private-server"
crawled: "2026-07-14"
---

# How to Use PS with Private Servers

This guide explains how to use Project Sylvanas (PS) with private servers, including our **Community Private Server** hosted for testing and development purposes.

## Why Use a Private Server?

Private servers are **perfect for testing** your plugins and rotations:

-   ⚡ **Instant leveling** - Skip the grind and test at any level
-   🗺️ **Instant travel** - Teleport anywhere without wasting time
-   🎯 **Target dummies** - Test DPS and rotations efficiently
-   👥 **Bot parties** - Run dungeons and raids with AI companions
-   🛡️ **Instant gear** - Equip BiS items for any bracket instantly
-   📚 **All spells** - Learn every spell without training
-   💰 **Free to use** - No subscription required

This is especially valuable for **WoW Classic** where leveling is slow and traveling takes forever. Save hours of testing time!

---

## Community Private Server

We maintain a **Community Private Server** for PS users, hosted by **PekingEnte**.

### Supported Versions

| Version | Expansion | Patch |
|---------|-----------|-------|
| Vanilla | Classic | 1.12 |
| TBC | The Burning Crusade | 2.4 |

### Server Features

Our community server comes with many quality-of-life features:

-   🤖 **Bot companions** for dungeons and raids
-   🎯 **Target dummies** everywhere for testing
-   🚕 **Custom taxi NPCs** with useful scripts:
    -   Instant equip BiS items for many bracket levels
    -   Teach all spells instantly
    -   Level adjustment
    -   And more...

### Getting an Account

To get an account on the Community Private Server:

1.  Contact **PekingEnte** on Discord
2.  Discord Username: `.mydayyy`
3.  Request an account for Vanilla, TBC, or both

> **Community Support**
> 
> PekingEnte is happy to help with questions about the private server setup. Don't hesitate to reach out!

---

## Quick Start - Community Server

If you just want to connect to our Community Private Server, follow these steps:

### Step 1: Download the Pre-Configured Client

**Vanilla 1.12:**

```
https://drive.google.com/file/d/1IAzFS4_Pex7N-uP-dZ90SvS8T5EMn-2i/view?usp=sharing
```

**TBC 2.4:**

```
https://drive.google.com/file/d/16OHt64nzE-TwekiNDartR_GmQByI-_h6/view?usp=sharing
```

### Step 2: Get an Account

Contact **PekingEnte** (Discord: `.mydayyy`) to request an account.

### Step 3: Launch and Play

1.  Extract the downloaded client
2.  Run `Start WoW Vanilla.cmd` or `Start WoW TBC.cmd`
3.  Login with your account credentials
4.  You're ready to test!

> **Pre-Configured**
> 
> These clients are already configured to connect to the Community Private Server. No additional setup required!

---

## Advanced - Running Your Own Server

If you prefer to run your own local server instead of using the Community Server, follow these instructions.

### Step 1: Download a WoW Repack

A "repack" is a pre-configured server package that runs on your local machine.

**Vanilla 1.12 Repack:**

```
https://mega.nz/file/HMU03IZJ#rHFo1hdT05f9xgWWcu9qdbAeX_nr4EkcCqTqEzD-W18
```

**TBC 2.4 Repack:**

```
https://mega.nz/file/vV0BxSbT#hxlQ3edutb6cyIVySXjntR-tWKWMrfWIxtzR1HrLmCo
```

### Step 2: Start the Repack Server

1.  Extract the repack to a folder
2.  Run the server executable (usually `start.bat` or similar)
3.  Wait for the world server to fully load

### Step 3: Configure HermesProxy

You need to modify the HermesProxy configuration to point to your local server.

**Config file location:**

```
World of Warcraft TBC\Hermes Launcher\hermes_proxy\HermesProxy.config
```

**Change the server address:**

Find this line:

```
<add key="ServerAddress" value="maste.me" />
```

Change it to:

```
<add key="ServerAddress" value="127.0.0.1" />
```

### Step 4: Check the Port

> **Port Configuration**
> 
> This is a common issue! Make sure the port matches your repack's auth server port.

Find this line in the config:

```
<add key="ServerPort" value="3725" />
```

**Default auth port is usually `3724`**, but the pre-configured clients use `3725` because the Community Server runs multiple realms.

If connecting to a local repack, you may need to change it to:

```
<add key="ServerPort" value="3724" />
```

Check your repack's configuration to confirm the correct auth port.

### Step 5: Launch and Connect

1.  Run `Start WoW TBC.cmd` (or Vanilla equivalent) from the client folder
2.  Login with the default repack credentials: `admin` / `admin`
3.  You're connected to your local server!

---

## Configuration Summary

### Community Server (Default)

| Setting | Value |
|---------|-------|
| ServerAddress | `maste.me` |
| ServerPort | `3725` |
| Account | Request from PekingEnte |

### Local Server (Localhost)

| Setting | Value |
|---------|-------|
| ServerAddress | `127.0.0.1` |
| ServerPort | `3724` (check your repack) |
| Account | `admin` / `admin` |

---

## Troubleshooting

### "Unable to connect to server"

1.  **Check ServerAddress** - Is it `maste.me` (community) or `127.0.0.1` (local)?
2.  **Check ServerPort** - Community uses `3725`, local usually uses `3724`
3.  **Firewall** - Make sure the port isn't blocked
4.  **Server running** - If local, ensure the repack server is fully started

### "Invalid account or password"

-   **Community Server**: Contact PekingEnte for valid credentials
-   **Local Server**: Default is usually `admin` / `admin`

### "World server is down"

-   Wait for the repack's world server to fully initialize
-   Check the server console for errors
-   Some repacks take a few minutes to load all maps

---

## Downloads Summary

### Pre-Configured Clients (Community Server)

| Version | Link |
|---------|------|
| Vanilla 1.12 | [Google Drive](https://drive.google.com/file/d/1IAzFS4_Pex7N-uP-dZ90SvS8T5EMn-2i/view?usp=sharing) |
| TBC 2.4 | [Google Drive](https://drive.google.com/file/d/16OHt64nzE-TwekiNDartR_GmQByI-_h6/view?usp=sharing) |

### Server Repacks (Localhost)

| Version | Link |
|---------|------|
| Vanilla 1.12 | [MEGA](https://mega.nz/file/HMU03IZJ#rHFo1hdT05f9xgWWcu9qdbAeX_nr4EkcCqTqEzD-W18) |
| TBC 2.4 | [MEGA](https://mega.nz/file/vV0BxSbT#hxlQ3edutb6cyIVySXjntR-tWKWMrfWIxtzR1HrLmCo) |

---

## Tips

> **Use Community Server First**
> 
> We recommend starting with the Community Private Server. It's already configured, has useful QoL features, and PekingEnte can help if you have issues. Only set up a local server if you have specific needs.

**Testing Workflow:**

1.  Develop and test basic functionality on the private server
2.  Use instant leveling and gear to test at different levels
3.  Test edge cases with bot parties in dungeons
4.  Final validation on retail/official servers

> **No Modifications Needed**
> 
> The pre-configured clients from Google Drive are ready to use immediately. All the configuration instructions above are only for those who want to connect to their own local server instead.

---

## Contact

**Community Server Host:** PekingEnte  
**Discord Username:** `.mydayyy`

Feel free to reach out for:

-   Account requests
-   Server questions
-   Technical support
-   Feature requests

---

Happy testing! 🎮
