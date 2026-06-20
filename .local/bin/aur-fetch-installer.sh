#!/bin/bash

# Define directories and file paths
CONFIG_DIR="$HOME/.config/aur-package-checker-installer"
LOG_FILE="$CONFIG_DIR/aur_checker.log"
DISCOVERY_LOG="$CONFIG_DIR/new_malware_discoveries.txt"

# Ensure the configuration directory exists
mkdir -p "$CONFIG_DIR"

# Define the absolute default URL explicitly
DEFAULT_URL="https://md.archlinux.org/s/SxbqukK6IA/download"

# Strictly use the environment variable if defined, otherwise enforce the exact default URL
if [ -n "$MALWARE_LIST_URL" ]; then
    ACTIVE_URL="$MALWARE_LIST_URL"
else
    ACTIVE_URL="$DEFAULT_URL"
fi

NEW_MALWARE_DISCOVERED=false

# Define uppercase color variables consistently using ANSI-C quoting
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
BOLD_RED=$'\033[1;31m'
BLINK_BOLD_RED=$'\033[5;1;31m' # Blinking large alert formatting
NC=$'\033[0m' # No Color

# Helper function to view and color-code the logs
view_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}No log file found at: $LOG_FILE${NC}"
        exit 0
    fi

    echo -e "${BLUE}--- Displaying Color-Coded Logs ($LOG_FILE) ---${NC}"
    
    sed \
        -e "s/\[INFO\]/${BLUE}[INFO]${NC}/g" \
        -e "s/\[SUCCESS\]/${GREEN}[SUCCESS]${NC}/g" \
        -e "s/\[WARN\]/${YELLOW}[WARN]${NC}/g" \
        -e "s/\[ERROR\]/${RED}[ERROR]${NC}/g" \
        -e "s/\[CRITICAL\]/${BOLD_RED}[CRITICAL]${NC}/g" \
        "$LOG_FILE"
        
    exit 0
}

# Helper function to display help/usage info
show_help() {
    echo "Usage:"
    echo "  $0 [options] <aur-package-name1> [aur-package-name2] ...   (Check and install packages)"
    echo ""
    echo "Available Flags and Options:"
    echo "  -c, --check-all                  Download and run deep heuristic checks on packages being installed and their AUR dependencies."
    echo "  -l, --check-local                Scan your currently installed system packages against the malware list without installing anything."
    echo "  -v, --view-logs                  View the color-coded history log of script activities."
    echo "  -h, --help                       Show this complete help and usage message."
    echo ""
    echo "Environment Variables:"
    echo "  MALWARE_LIST_URL                 Override the source malware list feed URL."
    echo "                                   Current Active URL: $ACTIVE_URL"
    if [ "$ACTIVE_URL" = "$DEFAULT_URL" ]; then
        echo "                                   Status: Using default Arch Linux source."
    else
        echo -e "                                   Status: ${YELLOW}Using custom environment override.${NC}"
    fi
}

# Helper function to write to log file with timestamps
log_message() {
    local type="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] - $message" >> "$LOG_FILE"
}

# Helper function to record newly discovered malware to a dedicated shareable list
record_discovery() {
    local flagged_pkg="$1"
    local parent_pkg="$2"
    local code_found="$3"
    
    NEW_MALWARE_DISCOVERED=true

    # Create file with a header if it doesn't exist yet
    if [ ! -f "$DISCOVERY_LOG" ]; then
        echo "AUR Malware Discovery Log - Generated for Sharing" > "$DISCOVERY_LOG"
        echo "=================================================" >> "$DISCOVERY_LOG"
    fi

    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$DISCOVERY_LOG"
    echo "Package: $flagged_pkg" >> "$DISCOVERY_LOG"
    if [ -n "$parent_pkg" ]; then
        echo "Found As: Dependency of '$parent_pkg'" >> "$DISCOVERY_LOG"
    fi
    echo "Flagged Code / Patterns:" >> "$DISCOVERY_LOG"
    echo "$code_found" >> "$DISCOVERY_LOG"
    echo "-------------------------------------------------" >> "$DISCOVERY_LOG"
}

# Subroutine to scan currently installed local packages against the known malware database
check_local_system() {
    echo "Scanning local system for known compromised packages..."
    local found_malware=false
    local flagged_pkgs=""

    # Optimize matching by isolating pure package names from the fetched malware list
    local clean_malware_list
    clean_malware_list=$(echo "$COMPROMISED_LIST" | sed -E 's/^\*[[:space:]]*//' | awk '{print $1}' | sed -E 's/[<>=].*//')

    # Get a strict list of EXACT package names installed on the system, bypassing "provides" aliases.
    local installed_pkgs
    installed_pkgs=$(pacman -Qq)

    for bad_pkg in $clean_malware_list; do
        [ -z "$bad_pkg" ] && continue
        
        # Check if the bad package name exists as an exact, full-line match in the installed list
        if echo "$installed_pkgs" | grep -Fqx "$bad_pkg"; then
            found_malware=true
            flagged_pkgs="$flagged_pkgs $bad_pkg"
        fi
    done

    if [ "$found_malware" = true ]; then
        echo -e "${BLINK_BOLD_RED}"
        echo "██████████████████████████████████████████████████████████████████████"
        echo "██ CRITICAL ALERT: COMPROMISED PACKAGES FOUND ON YOUR SYSTEM        ██"
        echo "██████████████████████████████████████████████████████████████████████"
        echo -e "${NC}"
        echo -e "${RED}The following currently installed packages match the malware database:${NC}"
        for fp in $flagged_pkgs; do
            echo -e "  - ${BOLD_RED}$fp${NC}"
        done
        echo ""
        echo -e "${YELLOW}HALTING EXECUTION. You must correct this and remove the affected packages before installing anything else.${NC}"
        log_message "CRITICAL" "Local scan halted execution. Compromised packages found on the system: $flagged_pkgs"
        return 1
    else
        return 0
    fi
}

# Subroutine to deep-scan extracted source code for malware patterns
scan_source_files() {
    local pkg_name="$1"
    
    echo "--- Running Advanced Heuristic Checks on Primary Package Source ---"
    
    # Extract sources without building (-o) or installing dependencies (-d)
    echo "Extracting sources for deeper inspection..."
    if ! makepkg -od >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARN] Could not automatically extract sources for $pkg_name. Skipping deep source scan.${NC}"
        return 0
    fi

    if [ ! -d "src" ]; then
        echo -e "${YELLOW}[WARN] No src/ directory found after extraction. Skipping deep source scan.${NC}"
        return 0
    fi

    # Known malware programming patterns
    local patterns="curl.*\|.*bash|wget.*\|.*sh|stratum\+tcp|xmrig|/dev/tcp/|nc\ -e\ /bin/(ba)?sh|eval.*base64"
    
    echo "Scanning extracted source code in src/ directory..."
    local suspicious_matches
    suspicious_matches=$(grep -r -iE -n "$patterns" "src/" 2>/dev/null)

    if [ -n "$suspicious_matches" ]; then
        echo -e "${RED}WARNING: Suspicious programming patterns detected in source files!${NC}"
        echo -e "${RED}$suspicious_matches${NC}"
        log_message "WARN" "Malware patterns found in source of '$pkg_name'. Review required."
        record_discovery "$pkg_name" "" "$suspicious_matches"
        return 1
    else
        echo -e "${GREEN}No obvious malicious patterns found in the primary package source code.${NC}"
        return 0
    fi
}

# Explicitly check for zero arguments passed before starting any processing
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Parse command line arguments
CHECK_ALL_DEPS=false
CHECK_LOCAL_ONLY=false
PACKAGES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --view-logs|-v)
            view_logs
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --check-all|-c)
            CHECK_ALL_DEPS=true
            shift
            ;;
        --check-local|-l)
            CHECK_LOCAL_ONLY=true
            shift
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            PACKAGES+=("$1")
            shift
            ;;
    esac
done

# Exit if flags were parsed but no actionable parameters remain
if [ ${#PACKAGES[@]} -eq 0 ] && [ "$CHECK_LOCAL_ONLY" = false ]; then
    if [ "$CHECK_ALL_DEPS" = true ]; then
        echo -e "${RED}Error: You used the -c flag, but didn't provide any package names to check/install!${NC}\n"
    fi
    show_help
    exit 1
fi

# Save script entry working directory absolutely
SCRIPT_EXEC_DIR="$(pwd)"

echo "Logging session to: $LOG_FILE"
echo "Target Malware Database: $ACTIVE_URL"

echo -e "${GREEN}Fetching the latest compromised packages list...${NC}"
COMPROMISED_LIST=$(curl -sL "$ACTIVE_URL" | tr -d '\r')

if [ -z "$COMPROMISED_LIST" ]; then
    echo -e "${RED}Failed to fetch the compromised packages list. Aborting for safety.${NC}"
    log_message "ERROR" "Failed to download compromised packages list from $ACTIVE_URL. Session aborted."
    exit 1
fi

# If the user only wants to check the local system
if [ "$CHECK_LOCAL_ONLY" = true ]; then
    log_message "INFO" "Running standalone local system integrity check."
    if check_local_system; then
        local_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${GREEN}All clear, no compromised packages found on $local_date installed on your system.${NC}"
        log_message "SUCCESS" "Local system scan passed cleanly."
    fi
    exit 0
fi

# For standard package installation sessions
if [ "$CHECK_ALL_DEPS" = true ]; then
    echo -e "${BLUE}Deep Dependency Checking: ENABLED${NC}"
fi
log_message "INFO" "Starting session for packages: ${PACKAGES[*]} Using URL: $ACTIVE_URL"

# ALWAYS verify the local system is safe before allowing an install session to proceed
if ! check_local_system; then
    exit 1
fi

is_compromised() {
    local check_pkg="$1"
    local clean_name=$(echo "$check_pkg" | sed -E 's/[<>=].*//') 
    
    if echo "$COMPROMISED_LIST" | grep -Eiq "(^|[[:space:]]|\*)$clean_name([[:space:]]|$)"; then
        return 0
    else
        return 1
    fi
}

for PKG in "${PACKAGES[@]}"; do
    echo "--------------------------------------------------"
    echo -e "Processing package: ${GREEN}$PKG${NC}"
    echo "--------------------------------------------------"
    log_message "INFO" "Processing package: $PKG"
    
    # Keep BUILD_DIR relative to the directory we execute from, or clean absolute path
    BUILD_DIR="/tmp/aur_checker_$PKG"

    echo "Checking main package: '$PKG'..."
    if is_compromised "$PKG"; then
        echo -e "${RED}CRITICAL WARNING: '$PKG' is on the known compromised/malware list!${NC}"
        echo "Source URL: $ACTIVE_URL"
        echo -e "${RED}Skipping '$PKG'.${NC}"
        log_message "CRITICAL" "Package '$PKG' is flagged on the malware list! Skipped."
        continue
    fi

    echo -e "${GREEN}Main package '$PKG' is clear.${NC}"
    echo ""

    echo "Fetching '$PKG' from the AUR to analyze dependencies..."
    rm -rf "$BUILD_DIR"
    
    # Explicitly run git clone targeting the correct AUR URL
    if ! git clone "https://aur.archlinux.org/${PKG}.git" "$BUILD_DIR" >/dev/null 2>&1; then
        echo -e "${RED}Failed to download $PKG. Does it exist?${NC}"
        log_message "ERROR" "Failed to clone $PKG from AUR. Skipped."
        continue
    fi

    cd "$BUILD_DIR" || continue

    echo "Extracting and checking dependencies against known database..."
    DEPS=$(makepkg --printsrcinfo 2>/dev/null | awk -F' = ' '/depends/ {print $2}' | sed -E 's/[<>=].*//' | sort -u)

    COMPROMISED_DEP_FOUND=false

    if [ -n "$DEPS" ]; then
        for dep in $DEPS; do
            if is_compromised "$dep"; then
                echo -e "${RED}CRITICAL WARNING: Dependency '$dep' is on the compromised list!${NC}"
                log_message "CRITICAL" "Package '$PKG' relies on compromised dependency '$dep'!"
                COMPROMISED_DEP_FOUND=true
            fi
        done
        
        # New deep heuristic check for dependencies
        if [ "$CHECK_ALL_DEPS" = true ] && [ "$COMPROMISED_DEP_FOUND" = false ]; then
            echo ""
            echo "--- Running Heuristic Checks on Dependencies ---"
            for dep in $DEPS; do
                DEP_BUILD_DIR="/tmp/aur_checker_dep_$dep"
                rm -rf "$DEP_BUILD_DIR"
                
                # Attempt to clone. If it fails, it is likely an official repo package (not AUR).
                if git clone "https://aur.archlinux.org/${dep}.git" "$DEP_BUILD_DIR" >/dev/null 2>&1; then
                    echo "Scanning AUR dependency '$dep'..."
                    DEP_SUSPICIOUS=$(grep -iE -n "curl.*\|.*bash|wget.*\|.*bash|base64\s*-d|rm\s*-rf\s*/|mkfs|dd\s+if=" "$DEP_BUILD_DIR/PKGBUILD" "$DEP_BUILD_DIR/"*.install 2>/dev/null)
                    
                    if [ -n "$DEP_SUSPICIOUS" ]; then
                        echo -e "${RED}CRITICAL WARNING: Suspicious heuristics found in dependency '$dep'!${NC}"
                        echo -e "${RED}$DEP_SUSPICIOUS${NC}"
                        log_message "CRITICAL" "Malware patterns found in dependency '$dep' of package '$PKG'."
                        record_discovery "$dep" "$PKG" "$DEP_SUSPICIOUS"
                        COMPROMISED_DEP_FOUND=true
                    fi
                else
                    echo -e "${BLUE}Dependency '$dep' is likely an official package (not in AUR). Skipped heuristics.${NC}"
                fi
                
                rm -rf "$DEP_BUILD_DIR"
                
                # Halt further dependency checks if a compromised one was found
                if [ "$COMPROMISED_DEP_FOUND" = true ]; then
                    break
                fi
            done
        fi
    else
        echo -e "${GREEN}(No dependencies found or extraction completed smoothly)${NC}"
    fi

    if [ "$COMPROMISED_DEP_FOUND" = true ]; then
        echo -e "${RED}Installation skipped for '$PKG' due to compromised dependencies.${NC}"
        log_message "WARN" "Skipped '$PKG' installation due to unsafe dependencies."
        echo "Cleaning up..."
        rm -rf "$BUILD_DIR"
        cd "$SCRIPT_EXEC_DIR"
        continue
    fi

    echo -e "${GREEN}All dependencies are clear.${NC}"
    echo ""

    # Basic check on the AUR package files specifically
    echo "--- Running Basic Heuristic Checks on Main AUR Files ---"
    SUSPICIOUS=$(grep -iE -n "curl.*\|.*bash|wget.*\|.*bash|base64\s*-d|rm\s*-rf\s*/|mkfs|dd\s+if=" PKGBUILD *.install 2>/dev/null)

    if [ -n "$SUSPICIOUS" ]; then
        echo -e "${RED}WARNING: Suspicious patterns detected in AUR build files!${NC}"
        echo -e "${RED}$SUSPICIOUS${NC}"
        echo -e "${RED}Skipping '$PKG' for your safety. Please review files in $BUILD_DIR manually.${NC}"
        log_message "WARN" "Suspicious heuristics found in '$PKG' PKGBUILD. Skipping installation."
        record_discovery "$PKG" "" "$SUSPICIOUS"
        cd "$SCRIPT_EXEC_DIR"
        continue
    else
        echo -e "${GREEN}No obvious malicious patterns found in the main PKGBUILD or install files.${NC}"
    fi

    echo ""
    # Deep check on the source files
    if ! scan_source_files "$PKG"; then
        echo -e "${RED}Skipping '$PKG' for your safety. Please review extracted files in $BUILD_DIR/src manually.${NC}"
        cd "$SCRIPT_EXEC_DIR"
        continue
    fi

    echo ""
    echo "--- Manual Review ---"
    echo "It is highly recommended to review the PKGBUILD before installing."
    read -p "Would you like to read the PKGBUILD for $PKG now? (Y/n) " view_pkg
    if [[ "$view_pkg" =~ ^[Yy]$ ]] || [[ -z "$view_pkg" ]]; then
        less PKGBUILD
    fi

    echo ""
    read -p "Do you want to build and install $PKG? (y/N) " do_install
    if [[ "$do_install" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Building package...${NC}"
        # Only build and sync dependencies here; do not install yet
        if makepkg -s; then
            # Locate the built package archive (accounts for .pkg.tar.zst, .pkg.tar.xz, etc.)
            PKG_ARCHIVE=$(find . -maxdepth 1 -type f -name "*.pkg.tar.*" | head -n 1)
            
            if [ -n "$PKG_ARCHIVE" ]; then
                echo -e "${GREEN}Installing/Updating '$PKG' and overwriting conflicts...${NC}"
                # Use pacman directly to forcefully overwrite existing tracking conflicts
                if sudo pacman -U --overwrite '*' "$PKG_ARCHIVE"; then
                    log_message "SUCCESS" "Successfully built and installed/updated '$PKG'."
                else
                    echo -e "${RED}Installation failed during the pacman phase.${NC}"
                    log_message "ERROR" "pacman failed to install '$PKG'."
                fi
            else
                echo -e "${RED}Could not locate the built package archive. Installation aborted.${NC}"
                log_message "ERROR" "makepkg succeeded but no archive was found for '$PKG'."
            fi
        else
            log_message "ERROR" "makepkg failed during the build process of '$PKG'."
        fi
    else
        echo -e "${RED}Installation for $PKG cancelled.${NC}"
        log_message "INFO" "User cancelled the installation for '$PKG'."
    fi

    # Cleanup package specific build directory safely
    rm -rf "$BUILD_DIR"
    cd "$SCRIPT_EXEC_DIR"
    echo ""
done

echo -e "${GREEN}All package checks and installations completed!${NC}"

# Final alert for newly discovered malware
if [ "$NEW_MALWARE_DISCOVERED" = true ]; then
    echo ""
    echo -e "${BOLD_RED}*** ATTENTION: NEW MALICIOUS PATTERNS DISCOVERED ***${NC}"
    echo -e "${YELLOW}One or more packages/dependencies were flagged during heuristic scanning.${NC}"
    echo -e "${YELLOW}The findings have been saved to:${NC} ${BLUE}$DISCOVERY_LOG${NC}"
    echo -e "${YELLOW}Please review this file and share it with the community to update the master list.${NC}"
fi

log_message "INFO" "Session completed successfully."