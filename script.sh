#!/usr/bin/env bash
set -ue

# Thanks for being nosy, this script is harmless, everything is as safe as it gets.

# colors
RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[94m"
YELLOW="\e[33m"
BOLD="\e[1m"
ITALIC="\e[3m"
CLR="\e[0m"

# some basic config, please don't touch unless you know what you are doing
MCBE="$HOME/.mcbe"
PROTON_URL="https://github.com/Weather-OS/GDK-Proton/releases/download/release/GE-Proton10-25.tar.gz"
PROTON_DIR="$MCBE/proton"
PROXYPASS_URL="https://github.com/Kas-tle/ProxyPass/releases/download/master-58/ProxyPass.jar"
CURL_MINGW_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst"
CACERT_URL="https://curl.se/ca/cacert.pem"
FLARIAL_URL="https://cdn.discordapp.com/attachments/1455194805020921927/1459226183362154721/Flarial.dll?ex=69632a89&is=6961d909&hm=25473bbb87b5ffed841e7034f34303ce734275a0bd7245117bc4cc08a4403bf4&"

# helpers
step() {
    echo "==> $1"
}

confirm() {
    read -rp "==> $(printf "$1") [Y/n] " ans
    [[ "$ans" == "" || "$ans" =~ ^[Yy]$ ]]
}

error() {
    echo -e "${RED}ERROR:${CLR} $1"

    echo "Typically after an error, you'll probably want to start fresh for the next run of this script."
    confirm "Delete the game root?" && confirm "Are you sure?" || exit 1

    # Scary!
    rm -rf "$MCBE"
    exit 1
}

warn() {
    echo -e "${YELLOW}WARN:${CLR} $1"
}

info() {
    echo -e "${BLUE}INFO:${CLR} $1"
}

ok () {
    echo -e "${GREEN}OK:${CLR} $1"
}

is_lutris_installed() {
    if command -v lutris >/dev/null 2>&1; then
        return 0
    fi

    if pacman -Qs lutris >/dev/null; then
        return 0
    fi

    if command -v flatpak >/dev/null 2>&1 && flatpak list | grep -q "^net.lutris.Lutris"; then
        return 0
    fi

    return 1
}

# -------------------------------------------------------------
if ! grep -qi "arch" /etc/os-release; then
    error "This script can run only on Arch Linux (or a derivative). Sorry!"
fi

# -------------------------------------------------------------
echo -e "\nHello! This little script will (mostly) ${GREEN}install and set up Minecraft GDK${CLR} on ${BLUE}Arch${CLR}.\n"\
"In order to continue, you ${RED}must provide a zip which contains your game${CLR}.\n\n"\
"To obtain it, you'll have to:\n"\
" ${BOLD}-${CLR} Set up a Windows VM (10/11)\n"\
" ${BOLD}-${CLR} Download the Xbox app and in it, Minecraft for Windows\n"\
" ${BOLD}-${CLR} Find where the game is installed, go into the Content folder\n"\
" ${BOLD}-${CLR} ${BOLD}MOVE${CLR} Minecraft.Windows.exe to your Desktop, then ${BOLD}COPY${CLR} it back into the Content folder\n"\
" ${BOLD}-${CLR} Finally, zip up the files and move them to Linux in any way you see fit.\n\n"\
"You will soon be asked to provide a file path to the archive you just made."

confirm "Ready?" || exit 1

# -------------------------------------------------------------
step "Detecting GPU"
GPU="$(lspci | grep -Ei 'vga|3d' | grep -Ei 'nvidia|amd|ati|intel' || true)"

if echo "$GPU" | grep -qi nvidia; then
    GPU_TYPE="nvidia"
elif echo "$GPU" | grep -Eqi 'amd|ati'; then
    GPU_TYPE="amd"
elif echo "$GPU" | grep -qi intel; then
    GPU_TYPE="intel"
else
    GPU_TYPE="unknown"
fi

echo $GPU
echo "Detected GPU: $GPU_TYPE"

confirm "Is this correct?" || exit 1

# -------------------------------------------------------------
step "Enable multilib"
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    confirm "Add multilib repository?" && sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
else
    ok "Multilib already enabled."
fi

# -------------------------------------------------------------
step "Update system"
confirm "Run ${ITALIC}pacman -Syu${CLR}?" && sudo pacman -Syu --noconfirm

# -------------------------------------------------------------
step "Install dependencies"

# i'm sure not all of these are needed, but it doesn't hurt to get them
BASE_PKGS=(
    lib32-vulkan-icd-loader
    lib32-vulkan-mesa-implicit-layers
    lib32-vulkan-mesa-layers
    vulkan-icd-loader
    vulkan-mesa-implicit-layers
    vulkan-mesa-layers
    unzip
)

if [[ "$GPU_TYPE" == "nvidia" ]]; then
    GPU_PKGS=(nvidia-utils lib32-nvidia-utils)
else
    GPU_PKGS=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon)
fi

confirm "Install required packages?" && sudo pacman -S --needed --noconfirm "${BASE_PKGS[@]}" "${GPU_PKGS[@]}"

# -------------------------------------------------------------
step "Create directory structure"
mkdir -p "$MCBE"/{proton,proxy,client,game/Content,game/etc/ssl/certs}

# -------------------------------------------------------------
step "Import Minecraft data"

read -rp "==> Enter full path to your Content archive (zip or tar.*) (This will hang): " ARCHIVE
if [[ ! -f "$ARCHIVE" ]]; then
    error "File not found!"
fi

rm -rf "$MCBE/game/Content/"
mkdir -p "$MCBE/game/Content"

# detect achive extension
if [[ "$ARCHIVE" == *.zip ]]; then
    LIST_CMD=(unzip -l "$ARCHIVE")
    EXTRACT_CMD=(unzip -qo "$ARCHIVE" -d "$MCBE/game/Content")
elif [[ "$ARCHIVE" =~ \.tar\..* || "$ARCHIVE" == *.tar ]]; then
    LIST_CMD=(tar -tf "$ARCHIVE")
    EXTRACT_CMD=(tar -xf "$ARCHIVE" -C "$MCBE/game/Content")
else
    error "Unsupported file type! Please use .zip or .tar (of any kind)."
fi

CONTENTS="$("${LIST_CMD[@]}")"
"${EXTRACT_CMD[@]}"

# sanity check #1
TOP_LEVEL="$(find "$MCBE/game/Content" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

if [[ "$(basename "$TOP_LEVEL")" == "Content" ]]; then
    warn "Archive contains a Content folder, this means you zipped it incorrectly - fixing automatically."
    mv "$TOP_LEVEL"/* "$MCBE/game/Content/"
    rm -rf "$TOP_LEVEL"
    ok "Fixed Content layout."
else 
    ok "Archive layout seems correct."
fi 

info "Extracting into ${ITALIC}~/.mcbe/game/Content${CLR}"
"${EXTRACT_CMD[@]}"

# sanity check #2
if [[ ! -f "$MCBE/game/Content/Minecraft.Windows.exe" ]]; then
    error "No Minecraft.Windows.exe was found after extraction."
fi

rm "$MCBE/game/Content/XCurl.dll"
info "Removed XCurl.dll (will be replaced later)."

ok "Minecraft Content imported successfully."

# -------------------------------------------------------------
step "Install WineGDK"

if [[ -d "$PROTON_DIR/files" ]]; then
    ok "WineGDK is probably already installed."
else
    confirm "Download and install WineGDK?" && (
        cd "$MCBE"
        curl -LO "$PROTON_URL"
        tar -xf GE-Proton10-25.tar.gz

        rm -rf "$PROTON_DIR"
        mkdir -p "$PROTON_DIR"

        cp -r GE-Proton10-25/* "$PROTON_DIR/"
        rm -rf GE-Proton10-25 GE-Proton10-25.tar.gz
    )
fi

# -------------------------------------------------------------
step "Install ProxyPass"

if [[ -f "$MCBE/proxy/ProxyPass.jar" ]]; then
    ok "ProxyPass already installed."
else
    confirm "Download ProxyPass?" && (
        cd "$MCBE/proxy"
        curl -LO "$PROXYPASS_URL"
    )
fi

# -------------------------------------------------------------
step "ProxyPass login"

if confirm "Do you want to log in via Microsoft into ProxyPass?"; then
    cd "$MCBE/proxy"

    LOG="$MCBE/proxy/proxypass.log"
    rm -f "$LOG"

    echo -e "\nProxyPass will now start.\n"\
"A browser window will open.\n"\
"You will see a code shortly, use it to log in."
    echo

    # Start ProxyPass in background, logs hidden
    java -jar ProxyPass.jar > "$LOG" 2>&1 &
    PP_PID=$!

    CODE=""
    CODE_PRINTED=false
    SUCCESS=false

    # Poll log file
    while true; do
        sleep 0.5

        if [[ -f "$LOG" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ Enter\ code\ ([A-Z0-9]+) ]] && ! $CODE_PRINTED; then
                    CODE="${BASH_REMATCH[1]}"
                    info "Login code: $CODE"
                    CODE_PRINTED=true
                fi

                if echo "$line" | grep -q "Bedrock server started on"; then
                    SUCCESS=true
                    break
                fi
            done < "$LOG"
        fi

        $SUCCESS && break
    done

    ok "Login successful."

    # Stop ProxyPass cleanly
    kill "$PP_PID"
    wait "$PP_PID" 2>/dev/null || true
else
    info "Skipping Microsoft login. You can run ProxyPass manually later."
fi

# -------------------------------------------------------------
step "Configure ProxyPass server"

CFG="$MCBE/proxy/config.yml"

if [[ ! -f "$CFG" ]]; then
    warn "config.yml not found, skipping server configuration."
else
    echo -e "\nChoose a server:"
    echo "1) Cubecraft"
    echo "2) Hive"
    echo "3) Galaxite"
    echo "4) Lifeboat"
    echo "5) Mineville"

    read -rp "Select [1-5]: " choice

    case "$choice" in
        1) DEST_HOST="play.cubecraft.net" ;;
        2) DEST_HOST="geo.hivebedrock.network" ;;
        3) DEST_HOST="play.galaxite.net" ;;
        4) DEST_HOST="play.lbsg.net" ;;
        5) DEST_HOST="join.mineville.io" ;;
        *) DEST_HOST="play.cubecraft.net" ;;
    esac

    if [[ -n "$DEST_HOST" ]]; then
        sed -i 's/^\(\s*port:\).*/\1 19132/' "$CFG"
        sed -i "/destination:/,/port:/ s/^\(\s*host:\).*/\1 $DEST_HOST/" "$CFG"

        ok "ProxyPass configured"
    fi
fi


# -------------------------------------------------------------
step "Add patched XCurl.dll"
if [[ -f "$MCBE/game/Content/XCurl.dll" ]]; then
    ok "XCurl.dll already present."
else
    cd "$MCBE"
    curl -LO "$CURL_MINGW_URL"
    tar -xf mingw-w64-*.pkg.tar.zst

    cp mingw64/bin/libcurl-4.dll "$MCBE/game/Content/XCurl.dll"
    rm -rf mingw64 mingw-w64-*.pkg.tar.zst

    ok "Patched XCurl.dll"
fi

# -------------------------------------------------------------
step "Install SSL certificate"

if [[ -f "$MCBE/game/etc/ssl/certs/ca-bundle.crt" ]]; then
    ok "Certificate already installed."
else
    cd "$MCBE/game/etc/ssl/certs"
    curl -LO "$CACERT_URL"
    mv cacert.pem ca-bundle.crt

    ok "Certificates installed."
fi

# -------------------------------------------------------------
step "Download injector"

CLIENT=true

if [[ -f "$MCBE/client/injector.exe" ]]; then
    ok "Injector already exists."
else
    cd "$MCBE/client"
    curl -fLo injector.exe https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/injector/newloaderx64.exe

    ok "Injector installed"
fi

if [[ -f "$MCBE/client/client.dll" ]]; then
    ok "client.dll already exists."
else
    confirm "Will you be using a Minecraft client?" && (
        info "I'm too lazy to add auto-downloading. ${BOLD}Please add your dll into $MCBE/client and name it client.dll${CLR}"
    ) || CLIENT=false
fi

# -------------------------------------------------------------
step "Create start.sh"

if [[ -f "$MCBE/start.sh" ]]; then
    ok "start.sh already exists."
else
    if [ "$CLIENT" = false ]; then
        COMMENT="#"
        info "You have chosen to not use a client. If you change your mind, ${BOLD} add your dll into $MCBE/client and name it client.dll${CLR}, then ${BOLD}uncomment lines 3 and 4 in $MCBE/start.sh${CLR}"
    else
        COMMENT=""
    fi

    cat > "$MCBE/start.sh" <<EOF
#!/usr/bin/env bash

${COMMENT}sleep 10
${COMMENT}WINEFSYNC=1 WINEPREFIX=$MCBE/prefix $MCBE/proton/files/bin/wine64 $MCBE/client/injector.exe --lib "X:\.mcbe\client\client.dll" --procname "Minecraft.Windows.exe"

cd $MCBE/proxy
java -jar ProxyPass.jar
EOF

    chmod +x "$MCBE/start.sh"

    ok "Created start.sh."
fi

# -------------------------------------------------------------
step "Create exit.sh"

if [[ -f "$MCBE/exit.sh" ]]; then
    ok "exit.sh already exists."
else
    cat > "$MCBE/exit.sh" <<'EOF'
#!/usr/bin/env bash

pkill java
EOF
    chmod +x "$MCBE/exit.sh"

    ok "Created exit.sh."
fi

# -------------------------------------------------------------
step "Create Wine prefix"

if [[ -d "$MCBE/prefix" ]]; then
    ok "Wine prefix already exists."
else
    confirm "Initialize Wine prefix?" && (
        info "A winecfg window will pop up shortly, close it."
        WINEPREFIX="$MCBE/prefix" "$MCBE/proton/files/bin/wine64" winecfg >/dev/null 2>&1 || true
    )
fi

# -------------------------------------------------------------
step "Import necessary libraries"

confirm "Do you want to run umu-launcher to import required libraries?" && (
    info "umu-launcher will have to run once, it will add its libraries and you may launch the game from Lutris from that point on"
    info "A winecfg window will (again) pop up shortly, close it."
    sudo pacman -S --needed umu-launcher
    WINEPREFIX="$MCBE/prefix" PROTONPATH="$MCBE/proton" umu-run winecfg >/dev/null 2>&1 || true
)

# -------------------------------------------------------------
step "Check if Lutris is installed"

if is_lutris_installed; then
    ok "Lutris is already installed."
else
    info "Lutris is not installed"
    confirm "Install Lutris?" && (
        pacman -S --noconfirm lutris
    )
fi

echo -e "${GREEN}And we're done!${CLR}\n\n"\
"Now, all you have to do is add the game into Lutris. Follow this small guide:\n\n"\
"In Lutris, click the + icon in the top left corner and Add locally installed game\n"\
" - Name: Minecraft for Windows\n"\
" - Runner: Wine (If you get a warning about wine not being installed, ignore it)\n"\
"\n"\
"In the Game options tab:\n"\
" - Executable: $MCBE/game/Content/Minecraft.Windows.exe\n"\
" - Working directory: $MCBE/game/Content\n"\
" - Wine prefix: $MCBE/prefix\n"\
" - Prefix architecture: 64-bit\n"\
"\n"\
"Toggle the advanced switch in the top right corner.\n"\
"In the Runner options tab:\n"\
" - Wine version: Custom\n"\
" - Custom Wine executable: $MCBE/proton/files/bin/wine64\n"\
" - Enable DXVK, VKD3D, and D3D Extras\n"\
" - Enable Esync and Fsync\n"\
"\n"\
"In the System options tab:\n"\
" - GPU: Auto (Unless you're crashing, then set it to a specific device)\n"\
" - Pre-launch script: $MCBE/start.sh\n"\
" - Wait for pre-launch script completion: off\n"\
" - Post-exit script: $MCBE/exit.sh\n"\
"Save and pray it works!"
