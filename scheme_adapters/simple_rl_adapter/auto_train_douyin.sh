#!/bin/bash

# Automated training script for Douyin with auto-swipe simulation
# Auto-restarts on failure

# Configuration
APP_PACKAGE="com.ss.android.ugc.aweme"
TRAINING_ITERATIONS=50
SWIPE_INTERVAL=5  # seconds between swipes
PYTHON_BIN="venv/bin/python3"
SCRIPT="simple_rl_adapter_android.py"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to simulate swiping up (scrolling Douyin feed)
swipe_up() {
    # Get screen dimensions
    local width=$(adb shell wm size | grep -oP '\d+x\d+' | cut -d'x' -f1)
    local height=$(adb shell wm size | grep -oP '\d+x\d+' | cut -d'x' -f2)
    
    # Calculate swipe coordinates (center horizontally, from 80% to 20% vertically)
    local x=$((width / 2))
    local y_start=$((height * 80 / 100))
    local y_end=$((height * 20 / 100))
    local duration=300  # milliseconds
    
    # Perform swipe
    adb shell input swipe $x $y_start $x $y_end $duration 2>/dev/null
}

# Function to start background swiper
start_swiper() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] Starting auto-swiper (every ${SWIPE_INTERVAL}s)...${NC}"
    
    while true; do
        sleep $SWIPE_INTERVAL
        
        # Check if app is still running
        if adb shell pidof $APP_PACKAGE >/dev/null 2>&1; then
            swipe_up
            echo -e "${YELLOW}[$(date '+%H:%M:%S')] ↑ Swiped up${NC}"
        fi
    done &
    
    SWIPER_PID=$!
    echo -e "${GREEN}[$(date '+%H:%M:%S')] Auto-swiper started (PID: $SWIPER_PID)${NC}"
}

# Function to stop swiper
stop_swiper() {
    if [ ! -z "$SWIPER_PID" ] && kill -0 $SWIPER_PID 2>/dev/null; then
        echo -e "${YELLOW}[$(date '+%H:%M:%S')] Stopping auto-swiper...${NC}"
        kill $SWIPER_PID 2>/dev/null
        wait $SWIPER_PID 2>/dev/null
    fi
}

# Function to cleanup on exit
cleanup() {
    echo -e "\n${RED}[$(date '+%H:%M:%S')] Received interrupt signal${NC}"
    stop_swiper
    
    # Kill any running training process
    if [ ! -z "$TRAINING_PID" ] && kill -0 $TRAINING_PID 2>/dev/null; then
        echo -e "${YELLOW}[$(date '+%H:%M:%S')] Stopping training process...${NC}"
        kill $TRAINING_PID 2>/dev/null
        wait $TRAINING_PID 2>/dev/null
    fi
    
    echo -e "${GREEN}[$(date '+%H:%M:%S')] Cleanup complete. Exiting.${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main training loop with auto-restart
ATTEMPT=1
MAX_ATTEMPTS=10

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Automated Douyin Training with Auto-Swipe Simulation   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}App:${NC} $APP_PACKAGE"
echo -e "${YELLOW}Iterations:${NC} $TRAINING_ITERATIONS"
echo -e "${YELLOW}Swipe interval:${NC} ${SWIPE_INTERVAL}s"
echo -e "${YELLOW}Max retry attempts:${NC} $MAX_ATTEMPTS"
echo ""

# Check if ADB is connected
if ! adb devices | grep -q "device$"; then
    echo -e "${RED}Error: No ADB device connected!${NC}"
    echo "Please connect your Android device and enable USB debugging."
    exit 1
fi

# Check if app is installed
if ! adb shell pm list packages | grep -q "$APP_PACKAGE"; then
    echo -e "${RED}Error: Douyin app not installed!${NC}"
    echo "Package: $APP_PACKAGE"
    exit 1
fi

echo -e "${GREEN}[$(date '+%H:%M:%S')] Starting training loop...${NC}"
echo ""

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Attempt #${ATTEMPT}/${MAX_ATTEMPTS}${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    
    # Start the swiper in background
    start_swiper
    
    # Start training
    echo -e "${GREEN}[$(date '+%H:%M:%S')] Starting Q-Learning training...${NC}"
    $PYTHON_BIN $SCRIPT $APP_PACKAGE -n $TRAINING_ITERATIONS &
    TRAINING_PID=$!
    
    # Monitor training process
    if wait $TRAINING_PID; then
        # Training completed successfully
        EXIT_CODE=0
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              Training Completed Successfully!             ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        
        # Stop swiper
        stop_swiper
        
        echo -e "${GREEN}[$(date '+%H:%M:%S')] Check results at:${NC}"
        echo -e "  ${YELLOW}results/simple_rl_android/qvalue-${APP_PACKAGE}.txt${NC}"
        echo ""
        
        break
    else
        # Training failed
        EXIT_CODE=$?
        echo -e "\n${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                  Training Failed!                         ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${RED}[$(date '+%H:%M:%S')] Exit code: $EXIT_CODE${NC}"
        
        # Stop swiper
        stop_swiper
        
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            WAIT_TIME=10
            echo -e "${YELLOW}[$(date '+%H:%M:%S')] Waiting ${WAIT_TIME}s before retry...${NC}"
            sleep $WAIT_TIME
            ATTEMPT=$((ATTEMPT + 1))
        else
            echo -e "${RED}[$(date '+%H:%M:%S')] Max retry attempts reached. Giving up.${NC}"
            exit 1
        fi
    fi
    
    echo ""
done

echo -e "${GREEN}[$(date '+%H:%M:%S')] Script finished.${NC}"
exit 0
