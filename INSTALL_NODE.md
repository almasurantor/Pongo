# Installing Node.js on macOS

Node.js is required to run this project. Here are the easiest ways to install it:

## Option 1: Download from Official Website (Recommended)

1. Visit https://nodejs.org/
2. Download the **LTS (Long Term Support)** version for macOS
3. Run the installer (.pkg file)
4. Follow the installation wizard
5. Restart your terminal
6. Verify installation:
   ```bash
   node --version
   npm --version
   ```

## Option 2: Install Homebrew First, Then Node.js

If you prefer using a package manager:

1. **Install Homebrew** (if not already installed):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **Install Node.js**:
   ```bash
   brew install node
   ```

3. **Verify installation**:
   ```bash
   node --version
   npm --version
   ```

## After Installation

Once Node.js is installed, you can proceed with the project setup:

```bash
cd "/Users/almasur/Music/untitled folder/Pongo"
npm install
npm run dev
```

## Troubleshooting

- If `npm` is still not found after installation, try:
  - Closing and reopening your terminal
  - Restarting your computer
  - Checking that Node.js is in your PATH: `echo $PATH`

- If you see permission errors, you may need to fix npm permissions:
  ```bash
  mkdir ~/.npm-global
  npm config set prefix '~/.npm-global'
  echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.zshrc
  source ~/.zshrc
  ```
