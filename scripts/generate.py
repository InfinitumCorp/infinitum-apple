#!/usr/bin/env python3
"""Writes every product app's Product.json, app icon set, and project.yml from one table.

Run after changing PRODUCTS (needs Pillow):  python3 scripts/generate.py
Then on a Mac:  xcodegen generate && open Infinitum.xcodeproj
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ISSUERS = ["https://id.cumuluscloud.app", "https://ru.id.cumuluscloud.app"]

# Cumulus ID client ids and origins: infinitum-nexus packages/cid/src/id-clients.ts.
# analytics: Amplitude page views + sessions for commercial products. Off for VEIL (privacy
# guarantee), internal tools and defense products, per the standing rule.
PRODUCTS = [
    dict(target="Scalvs", id="scalvs", name="SCALVS.ai",
         tagline="Build agents that research, write, code, sell and operate for you.",
         clientId="scalvs", home="https://scalvs.app", mirrors=["https://ru.scalvs.app"],
         inAppHosts=["www.scalvs.app"], analytics=True, category="public.app-category.productivity"),
    dict(target="Metatron", id="metatron", name="METATRON¹⁰⁰™",
         tagline="Every Infinitum product in one AI command center for your life, your home and your business.",
         clientId="metatron", home="https://mttrn.app", inAppHosts=["www.mttrn.app"], analytics=True,
         category="public.app-category.productivity"),
    dict(target="Architect", id="architect", name=":\\ARCHITECT\\™",
         tagline="Describe an outcome. Architect plans it, does it, and proves it is done.",
         clientId="architect", home="https://rchtch.app", inAppHosts=["www.rchtch.app", "cndctr.app", "www.cndctr.app"],
         signIn="system", returnURL="https://rchtch.app/cid-return?to=desktop", callbackScheme="architect",
         handoffFragment=True, analytics=True, safari="Architect",
         category="public.app-category.developer-tools"),
    dict(target="Fabric", id="fabric", name="FabriC++™",
         tagline="Secure communications: encrypted messaging, voice and video with private AI.",
         clientId="fabric", home="https://infinitumfabric.app", inAppHosts=["www.infinitumfabric.app"],
         analytics=True, category="public.app-category.social-networking", mark="F++"),
    dict(target="FirmWallet", id="firm-wallet", name="$FIRM Wallet™",
         tagline="Self-custody for Solana, Ethereum and Base, with a built-in exchange for every Infinitum product token.",
         clientId="firm-wallet", home="https://firmwallet.app", inAppHosts=["www.firmwallet.app"],
         analytics=True, category="public.app-category.finance", mark="$FIRM"),
    dict(target="Firmament", id="firmament", name="$Firmament Network™",
         tagline="$FIRM™ settles every Infinitum product token.",
         clientId="firmament", home="https://firmnetwork.app", inAppHosts=["www.firmnetwork.app"],
         analytics=True, category="public.app-category.finance", mark="FIRM"),
    dict(target="Veil", id="veil", name="VEIL</>™",
         tagline="Infinitum's free, Tor-first secure browser.",
         clientId="veil", home="https://infinitumveil.app", inAppHosts=["www.infinitumveil.app"],
         analytics=False, category="public.app-category.utilities"),
    dict(target="VeilVPN", id="veil-vpn", name="VEIL</>™ VPN",
         tagline="Free, private, shared. No logs, tracker blocking and Tor over VPN.",
         clientId="veil-vpn", home="https://infinitumveilvpn.app", inAppHosts=["www.infinitumveilvpn.app"],
         analytics=False, category="public.app-category.utilities"),
]

INK = (0x11, 0x18, 0x20)
MAC_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in ["/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc",
                 "C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def master_icon(p: dict) -> Image.Image:
    """The product's real icon from Branding/, or a clean ink wordmark on white."""
    src = ROOT / "Branding" / f"{p['target']}.png"
    if src.exists():
        im = Image.open(src).convert("RGBA")
        canvas = Image.new("RGBA", im.size, (255, 255, 255, 255))
        canvas.alpha_composite(im)
        return canvas.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    im = Image.new("RGB", (1024, 1024), (255, 255, 255))
    d = ImageDraw.Draw(im)
    mark = p.get("mark", p["name"][:2])
    size = 420 if len(mark) <= 3 else 300
    f = font(size)
    while d.textlength(mark, font=f) > 820:
        size -= 20
        f = font(size)
    box = d.textbbox((0, 0), mark, font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((1024 - w) / 2 - box[0], (1024 - h) / 2 - box[1]), mark, fill=INK, font=f)
    return im


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def app_icon(p: dict, catalog: Path) -> None:
    icon_dir = catalog / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    master = master_icon(p)
    images = []
    master.save(icon_dir / "icon-1024.png")
    images.append({"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})
    for pt, scale in MAC_SIZES:
        px = pt * scale
        name = f"mac-{pt}@{scale}x.png"
        master.resize((px, px), Image.LANCZOS).save(icon_dir / name)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_json(icon_dir / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
    write_json(catalog / "Contents.json", {"info": {"author": "xcode", "version": 1}})


def product_json(p: dict) -> dict:
    out = {
        "id": p["id"],
        "name": p["name"],
        "tagline": p["tagline"],
        "clientId": p["clientId"],
        "home": p["home"],
        "mirrors": p.get("mirrors", []),
        "issuers": ISSUERS,
        "inAppHosts": p.get("inAppHosts", []),
        "signIn": p.get("signIn", "embedded"),
        "analytics": p["analytics"],
        "handoffFragment": p.get("handoffFragment", False),
    }
    if p.get("returnURL"):
        out["returnURL"] = p["returnURL"]
        out["callbackScheme"] = p["callbackScheme"]
    if p.get("safari"):
        out["safariExtension"] = f"app.infinitum.{p['id']}.safari"
    return out


def yaml_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def project_yml() -> str:
    lines = [
        "# Generated by scripts/generate.py. Edit the PRODUCTS table there, not this file.",
        "name: Infinitum",
        "options:",
        "  bundleIdPrefix: app.infinitum",
        "  developmentLanguage: en",
        "  deploymentTarget:",
        '    iOS: "17.0"',
        '    macOS: "14.0"',
        "settings:",
        "  base:",
        '    MARKETING_VERSION: "1.0.0"',
        '    CURRENT_PROJECT_VERSION: "1"',
        '    SWIFT_VERSION: "5.0"',
        "    GENERATE_INFOPLIST_FILE: YES",
        "    CODE_SIGN_STYLE: Automatic",
        '    DEVELOPMENT_TEAM: ""',
        "    # Public Amplitude API key, passed at build time (CI: repo variable AMPLITUDE_API_KEY).",
        "    # Empty means no analytics. Never the secret key.",
        '    AMPLITUDE_API_KEY: ""',
        "    DEAD_CODE_STRIPPING: YES",
        "packages:",
        "  InfinitumKit:",
        "    path: Packages/InfinitumKit",
        "targets:",
    ]
    for p in PRODUCTS:
        t = p["target"]
        lines += [
            f"  {t}:",
            "    type: application",
            "    supportedDestinations: [iOS, macOS]",
            "    scheme: {}",
            "    sources:",
            "      - path: Shell",
            f"      - path: Apps/{t}",
            "    dependencies:",
            "      - package: InfinitumKit",
        ]
        if p.get("safari"):
            lines += [f"      - target: {t}Safari"]
        lines += [
            "    info:",
            f"      path: Generated/{t}-Info.plist",
            "      properties:",
            f"        CFBundleDisplayName: {yaml_str(p['name'])}",
            "        AmplitudeAPIKey: $(AMPLITUDE_API_KEY)",
            "        UILaunchScreen: {}",
            "        ITSAppUsesNonExemptEncryption: false",
        ]
        if p.get("callbackScheme"):
            lines += [
                "        CFBundleURLTypes:",
                f"          - CFBundleURLName: app.infinitum.{p['id']}.cid",
                f"            CFBundleURLSchemes: [{p['callbackScheme']}]",
            ]
        lines += [
            "    settings:",
            "      base:",
            f"        PRODUCT_NAME: {t}",
            f"        PRODUCT_BUNDLE_IDENTIFIER: app.infinitum.{p['id']}",
            "        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
            '        TARGETED_DEVICE_FAMILY: "1,2"',
            "        SUPPORTS_MACCATALYST: NO",
            "        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES",
            "        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES",
            f"        INFOPLIST_KEY_LSApplicationCategoryType: {p['category']}",
            "        ENABLE_APP_SANDBOX: YES",
            "        ENABLE_OUTGOING_NETWORK_CONNECTIONS: YES",
            "        ENABLE_HARDENED_RUNTIME: YES",
        ]
        if p.get("safari"):
            e = p["safari"]
            lines += [
                f"  {t}Safari:",
                "    type: app-extension",
                "    supportedDestinations: [iOS, macOS]",
                "    sources:",
                f"      - path: Extensions/{e}/SafariWebExtensionHandler.swift",
                f"      - path: Extensions/{e}/Resources/manifest.json",
                "        buildPhase: resources",
            ]
            res = ROOT / "Extensions" / e / "Resources"
            for child in sorted(res.iterdir()) if res.exists() else []:
                if child.is_dir():
                    lines += [
                        f"      - path: Extensions/{e}/Resources/{child.name}",
                        "        type: folder",
                        "        buildPhase: resources",
                    ]
            lines += [
                "    info:",
                f"      path: Generated/{t}Safari-Info.plist",
                "      properties:",
                f"        CFBundleDisplayName: {yaml_str(p['name'])}",
                "        NSExtension:",
                "          NSExtensionPointIdentifier: com.apple.Safari.web-extension",
                "          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
                "    settings:",
                "      base:",
                f"        PRODUCT_NAME: {t}Safari",
                f"        PRODUCT_BUNDLE_IDENTIFIER: app.infinitum.{p['id']}.safari",
                '        TARGETED_DEVICE_FAMILY: "1,2"',
                "        SUPPORTS_MACCATALYST: NO",
                "        SKIP_INSTALL: YES",
                "        ENABLE_APP_SANDBOX: YES",
                "        ENABLE_OUTGOING_NETWORK_CONNECTIONS: YES",
                "        ENABLE_HARDENED_RUNTIME: YES",
            ]
    return "\n".join(lines) + "\n"


def main() -> int:
    for p in PRODUCTS:
        app = ROOT / "Apps" / p["target"]
        write_json(app / "Product.json", product_json(p))
        app_icon(p, app / "Assets.xcassets")
    (ROOT / "project.yml").write_text(project_yml(), encoding="utf-8")
    print(f"Wrote {len(PRODUCTS)} apps and project.yml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
