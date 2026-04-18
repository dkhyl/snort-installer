# 🛡️ Snort 3 Automated Installer

**Created by [dkhyl](https://github.com/dkhyl)**

[![Platform](https://img.shields.io/badge/platform-Linux-blue)](https://github.com/dkhyl/snort-installer)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A robust, cross-distribution Bash script that automates the complete installation of **Snort 3** from source. Say goodbye to dependency hell and manual compilation!

## ✨ Features

- 🔍 **Auto-detects** your Linux distribution (Ubuntu, Debian, Kali, Fedora, RHEL, Arch, openSUSE)
- 📦 **Installs all required dependencies** (including the often-missing `libfl-dev` for FlexLexer.h)
- 🧹 **Removes existing/broken Snort installations** before proceeding
- 🔧 **Builds libdaq and Snort 3** from official GitHub sources
- 🔗 **Creates a global symlink** – just type `snort` after installation!
- 🐚 **Automatically configures shell aliases** for `.bashrc` and `.zshrc`
- 💾 **Memory-aware** – creates temporary swap if RAM is low during compilation
- ✅ **Verifies installation** with version and DAQ module checks
- 📝 **Full logging** to `/tmp/` for easy troubleshooting

## 🚀 Quick Start

### 1. Update & Upgrade

```bash
sudo apt update -y
```
```bash
sudo apt upgrade -y
```
### 2. Install git & Clone the Repository
```bash
sudo apt install git -y
```
```bash
git clone https://github.com/dkhyl/snort-installer.git
```
```bash
cd snort-installer
```
### 3. Install dos2unix To Fix Line Endings 
```bash
sudo apt install dos2unix -y
```
```bash
dos2unix install_snort.sh
```
### 4. Make Script Executable
```bash
chmod +x install_snort.sh
```
### 5. Run Installer
```bash
sudo ./install_snort.sh
```
### 6. Verify Installation
```bash
snort -V
```
<p align="center">
  <img src="https://img.shields.io/badge/⏳_Compilation_Time-15--20_minutes-orange" alt="Compilation Time">
</p>
