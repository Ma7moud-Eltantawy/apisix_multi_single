#!/usr/bin/env python3
"""
==============================================================================
🏛️ Qyadati APISIX GitOps CLI Tool — Single-Flavor & Multi-Flavor Support
==============================================================================
Supports 2 Architecture Modes:
  1. SINGLE-FLAVOR MODE : Single unified file -> configs/apisix.yaml
  2. MULTI-FLAVOR MODE  : 5 isolated flavor files:
     - desktop      : Personal laptop / Docker Desktop
     - local        : On-premise LAN server
     - dev          : Shared cloud dev server
     - staging      : QA / UAT testing server
     - prod         : AWS Production VPC
==============================================================================
"""

import os
import sys
import json
import shutil
import argparse
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

# Ensure UTF-8 output on Windows consoles
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# --- ANSI Colors ---
class Colors:
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(title: str):
    print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*65}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.CYAN}[*] {title}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.CYAN}{'='*65}{Colors.RESET}")

def print_success(msg: str):
    print(f"{Colors.GREEN}[+] {msg}{Colors.RESET}")

def print_warning(msg: str):
    print(f"{Colors.YELLOW}[!] {msg}{Colors.RESET}")

def print_error(msg: str):
    print(f"{Colors.RED}[-] {msg}{Colors.RESET}")

def print_info(msg: str):
    print(f"{Colors.BLUE}[i] {msg}{Colors.RESET}")

# --- Paths & .env ---
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
ENV_FILE = PROJECT_ROOT / ".env"

def load_env_file():
    if not ENV_FILE.exists():
        return
    with open(ENV_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip("'\"")
            if key not in os.environ:
                os.environ[key] = val

load_env_file()

FLAVORS = {
    "desktop": {
        "name": "💻 Desktop (Personal Laptop / Docker Desktop)",
        "config": PROJECT_ROOT / "configs" / "flavors" / "desktop" / "apisix.yaml",
        "url": os.getenv("DESKTOP_APISIX_ADMIN_URL", "http://localhost:9181"),
        "token": os.getenv("DESKTOP_APISIX_ADMIN_TOKEN", os.getenv("ADMIN_KEY", "edd1c9f034335f136f87ad84b625c8f1"))
    },
    "local": {
        "name": "🏢 Local Server (On-Premise Office LAN)",
        "config": PROJECT_ROOT / "configs" / "flavors" / "local" / "apisix.yaml",
        "url": os.getenv("LOCAL_APISIX_ADMIN_URL", "http://192.168.1.50:9181"),
        "token": os.getenv("LOCAL_APISIX_ADMIN_TOKEN", os.getenv("ADMIN_KEY", "edd1c9f034335f136f87ad84b625c8f1"))
    },
    "dev": {
        "name": "🛠️ Dev Server (Shared Cloud Dev Gateway)",
        "config": PROJECT_ROOT / "configs" / "flavors" / "dev" / "apisix.yaml",
        "url": os.getenv("DEV_APISIX_ADMIN_URL", "https://dev-apisix.qyadati.internal:9181"),
        "token": os.getenv("DEV_APISIX_ADMIN_TOKEN", os.getenv("ADMIN_KEY", "edd1c9f034335f136f87ad84b625c8f1"))
    },
    "staging": {
        "name": "🧪 Staging / UAT Integration Server",
        "config": PROJECT_ROOT / "configs" / "flavors" / "staging" / "apisix.yaml",
        "url": os.getenv("STAGING_APISIX_ADMIN_URL", "https://staging-apisix.qyadati.internal:9181"),
        "token": os.getenv("STAGING_APISIX_ADMIN_TOKEN", os.getenv("ADMIN_KEY", "edd1c9f034335f136f87ad84b625c8f1"))
    },
    "prod": {
        "name": "🚀 Production Gateway (AWS Production VPC)",
        "config": PROJECT_ROOT / "configs" / "flavors" / "prod" / "apisix.yaml",
        "url": os.getenv("PROD_APISIX_ADMIN_URL", "https://prod-apisix.qyadati.internal:9181"),
        "token": os.getenv("PROD_APISIX_ADMIN_TOKEN", os.getenv("ADMIN_KEY", "edd1c9f034335f136f87ad84b625c8f1"))
    }
}

def check_adc_installed() -> bool:
    try:
        res = subprocess.run(["adc", "version"], capture_output=True, text=True)
        return res.returncode == 0
    except (FileNotFoundError, Exception):
        return False

def gateway_health_check(url: str, token: str) -> bool:
    target = f"{url.rstrip('/')}/apisix/admin/routes"
    req = urllib.request.Request(target, headers={"X-API-KEY": token})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status in (200, 201):
                return True
    except Exception as e:
        print_warning(f"Connection test failed to {target}: {e}")
        return False
    return False

def run_adc_validate(config_path: Path) -> bool:
    print_info(f"Validating: {config_path.name}")
    if not config_path.exists():
        print_error(f"File not found: {config_path}")
        return False
    res = subprocess.run(["adc", "validate", "-f", str(config_path)], capture_output=True, text=True)
    if res.returncode == 0:
        print_success(f"ADC Validation Passed for [{config_path.name}]!")
        return True
    else:
        print_error(f"ADC Validation Failed:")
        print(res.stderr or res.stdout)
        return False

def run_adc_diff(config_path: Path, url: str, token: str) -> bool:
    print_info(f"Running Dry-Run Diff against Gateway: {url}")
    cmd = ["adc", "diff", "-f", str(config_path), "--backend", "apisix", "--server", url, "--token", token]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(res.stdout)
    if res.stderr:
        print_warning(res.stderr)
    return res.returncode == 0

def run_adc_sync(config_path: Path, url: str, token: str) -> bool:
    print_info(f"Deploying to: {url} (Config: {config_path.name})")
    cmd = ["adc", "sync", "-f", str(config_path), "--backend", "apisix", "--server", url, "--token", token]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        print(res.stdout)
        print_success(f"ADC Sync completed with ZERO downtime on {url}!")
        return True
    else:
        print_error(f"ADC Sync Failed on {url}:")
        print(res.stderr or res.stdout)
        return False

def parse_simple_yaml(config_path: Path) -> bool:
    if not config_path.exists():
        return False
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
    if "routes:" in content and "name:" in content:
        print_success(f"Basic schema check OK for {config_path.name}")
        return True
    print_error(f"Invalid schema in {config_path.name}")
    return False

def interactive_menu():
    print_header("Qyadati APISIX GitOps CLI (Single-Flavor & Multi-Flavor)")
    adc_available = check_adc_installed()
    if adc_available:
        print_success("API7 ADC CLI Tool: DETECTED & READY")
    else:
        print_warning("API7 ADC CLI Tool: NOT FOUND in PATH.")

    print("\n--- 🎯 MODE 1: SINGLE-FLAVOR MODE ---")
    print(f"  [1] Single-Flavor Mode -> {FLAVORS['single']['config'].name}")

    print("\n--- 🌐 MODE 2: MULTI-FLAVOR ARCHITECTURE ---")
    print(f"  [2] {FLAVORS['desktop']['name']}")
    print(f"  [3] {FLAVORS['local']['name']}")
    print(f"  [4] {FLAVORS['dev']['name']}")
    print(f"  [5] {FLAVORS['staging']['name']}")
    print(f"  [6] {FLAVORS['prod']['name']}")
    print("  [7] Validate ALL Configurations (Single + All Flavors)")
    print("  [0] Exit")

    try:
        choice = input("\nEnter choice [0-7]: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nExiting.")
        sys.exit(0)

    mapping = {
        "1": "single",
        "2": "desktop",
        "3": "local",
        "4": "dev",
        "5": "staging",
        "6": "prod"
    }

    if choice == "0":
        print("Goodbye!")
        sys.exit(0)
    elif choice == "7":
        print_header("Validating All Configurations")
        all_passed = True
        for key, info in FLAVORS.items():
            if adc_available:
                passed = run_adc_validate(info["config"])
            else:
                passed = parse_simple_yaml(info["config"])
            if not passed:
                all_passed = False
        if all_passed:
            print_success("\nAll configurations validated successfully!")
        return

    selected_key = mapping.get(choice)
    if not selected_key:
        print_error("Invalid choice!")
        return

    target = FLAVORS[selected_key]
    print_header(f"Selected: {target['name']}")
    print(f"Config File : {target['config']}")
    print(f"Gateway URL : {target['url']}")
    
    print("\nSelect Action:")
    print("  [1] Validate Configuration (adc validate)")
    print("  [2] Diff / Dry-Run Preview (adc diff)")
    print("  [3] Sync / Hot-Reload Gateway (adc sync - ZERO DOWNTIME)")
    print("  [4] Health Check Gateway Admin API")
    print("  [0] Back")

    try:
        act_choice = input("\nEnter action [1-4]: ").strip()
    except (KeyboardInterrupt, EOFError):
        return

    if act_choice == "1":
        if adc_available:
            run_adc_validate(target["config"])
        else:
            parse_simple_yaml(target["config"])
    elif act_choice == "2":
        if adc_available:
            run_adc_diff(target["config"], target["url"], target["token"])
        else:
            print_error("ADC CLI tool is required for diff preview.")
    elif act_choice == "3":
        confirm = input(f"\nAre you sure you want to sync [{selected_key}] to {target['url']}? (y/N): ").strip().lower()
        if confirm == 'y':
            if adc_available:
                run_adc_sync(target["config"], target["url"], target["token"])
            else:
                print_error("ADC CLI tool is required for sync. Please install adc.")
        else:
            print_info("Sync cancelled.")
    elif act_choice == "4":
        print_info(f"Pinging Admin API at {target['url']}...")
        if gateway_health_check(target["url"], target["token"]):
            print_success(f"Gateway Admin API at {target['url']} is HEALTHY and REACHABLE!")
        else:
            print_error(f"Gateway Admin API at {target['url']} is UNREACHABLE. Check URL/Token/Network.")

def main():
    parser = argparse.ArgumentParser(description="Qyadati APISIX GitOps CLI (Single & Multi-Flavor)")
    parser.add_argument("--flavor", "-f", choices=["single", "desktop", "local", "dev", "staging", "prod", "all"], help="Target Flavor / Mode")
    parser.add_argument("--action", "-a", choices=["validate", "diff", "sync", "health"], help="Action to perform")
    parser.add_argument("--url", help="Override APISIX Admin API URL")
    parser.add_argument("--token", help="Override APISIX Admin API Token")

    args = parser.parse_args()

    if not args.flavor and not args.action:
        interactive_menu()
        return

    adc_available = check_adc_installed()
    
    if args.flavor == "all":
        print_header("Validating All Configurations")
        all_passed = True
        for key, info in FLAVORS.items():
            if adc_available:
                passed = run_adc_validate(info["config"])
            else:
                passed = parse_simple_yaml(info["config"])
            if not passed:
                all_passed = False
        sys.exit(0 if all_passed else 1)

    flavor_info = FLAVORS.get(args.flavor or "single")
    url = args.url or flavor_info["url"]
    token = args.token or flavor_info["token"]
    config_file = flavor_info["config"]

    if args.action == "validate":
        if adc_available:
            sys.exit(0 if run_adc_validate(config_file) else 1)
        else:
            sys.exit(0 if parse_simple_yaml(config_file) else 1)
    elif args.action == "diff":
        if not adc_available:
            print_error("ADC CLI tool required for diff action.")
            sys.exit(1)
        sys.exit(0 if run_adc_diff(config_file, url, token) else 1)
    elif args.action == "sync":
        if not adc_available:
            print_error("ADC CLI tool required for sync action.")
            sys.exit(1)
        sys.exit(0 if run_adc_sync(config_file, url, token) else 1)
    elif args.action == "health":
        is_healthy = gateway_health_check(url, token)
        if is_healthy:
            print_success(f"Gateway {url} is healthy.")
            sys.exit(0)
        else:
            print_error(f"Gateway {url} is unreachable.")
            sys.exit(1)

if __name__ == "__main__":
    main()
