#EXAMPLE_SH
# SuperForgeRW - Modularized Entry Point

# Source the main orchestrator script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/src/main.sh" "$@"
