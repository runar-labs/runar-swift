#!/bin/bash

set -e  # Exit on any error

# Paths
SWIFT_DIR="/Users/rafael/dev/runar-swift/swift-ffi"
RUST_RELEASE_DIR="/Users/rafael/dev/runar-swift/runar-rust/target/debug"
DYLIB_PATH="${RUST_RELEASE_DIR}/librunar_ffi.dylib"
XCTEST_PATH="${SWIFT_DIR}/.build/arm64-apple-macosx/debug/swift-ffiPackageTests.xctest"
ENTITLEMENTS="${SWIFT_DIR}/entitlements.plist"
DEBUGSERVER_ENTITLEMENTS="${SWIFT_DIR}/debugserver-entitlements.plist"
DEBUGSERVER_ORIG_PATH="/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/Resources/debugserver"
CUSTOM_DEBUGSERVER_DIR="${SWIFT_DIR}/MyDebugserver.app/Contents/MacOS"
CUSTOM_DEBUGSERVER_PATH="${CUSTOM_DEBUGSERVER_DIR}/MyDebugserver"
LOG_FILE="/tmp/run_tests_output/combined.log"
OUTPUT_DIR="/tmp/run_tests_output"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${CUSTOM_DEBUGSERVER_DIR}"

# Initialize combined log file
echo "===== Combined Log File: $(date) =====" > "${LOG_FILE}"

echo "Starting test execution script..." | tee -a "${LOG_FILE}"

# Step 1: Verify prerequisites
echo "Checking prerequisites..." | tee -a "${LOG_FILE}"

# Check entitlements.plist
if [ ! -f "${ENTITLEMENTS}" ]; then
    echo "Error: entitlements.plist not found at ${ENTITLEMENTS}" | tee -a "${LOG_FILE}"
    echo "Creating default entitlements.plist..." | tee -a "${LOG_FILE}"
    cat > "${ENTITLEMENTS}" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
EOL
fi

# Validate entitlements.plist syntax
echo "===== Validating entitlements.plist =====" >> "${LOG_FILE}"
if ! plutil "${ENTITLEMENTS}" | grep -q "OK"; then
    echo "Error: Invalid entitlements.plist syntax" | tee -a "${LOG_FILE}"
    plutil "${ENTITLEMENTS}" >> "${LOG_FILE}" 2>&1
    exit 1
fi
plutil "${ENTITLEMENTS}" >> "${LOG_FILE}" 2>&1

# Check for get-task-allow entitlement
if ! grep -q "com.apple.security.get-task-allow" "${ENTITLEMENTS}"; then
    echo "Error: entitlements.plist does not contain com.apple.security.get-task-allow" | tee -a "${LOG_FILE}"
    cat "${ENTITLEMENTS}" >> "${LOG_FILE}"
    exit 1
fi

# Create debugserver-entitlements.plist
if [ ! -f "${DEBUGSERVER_ENTITLEMENTS}" ]; then
    echo "Creating debugserver-entitlements.plist..." | tee -a "${LOG_FILE}"
    cat > "${DEBUGSERVER_ENTITLEMENTS}" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
EOL
fi

# Check dylib existence
if [ ! -f "${DYLIB_PATH}" ]; then
    echo "Error: Rust dylib not found at ${DYLIB_PATH}" | tee -a "${LOG_FILE}"
    echo "Contents of ${RUST_RELEASE_DIR}:" >> "${LOG_FILE}"
    ls -l "${RUST_RELEASE_DIR}" >> "${LOG_FILE}"
    exit 1
fi

# Check debugserver existence
if [ ! -f "${DEBUGSERVER_ORIG_PATH}" ]; then
    echo "Error: original debugserver not found at ${DEBUGSERVER_ORIG_PATH}" | tee -a "${LOG_FILE}"
    echo "Please install full Xcode from the App Store." | tee -a "${LOG_FILE}"
    exit 1
fi
echo "Found original debugserver at ${DEBUGSERVER_ORIG_PATH}" | tee -a "${LOG_FILE}"

# Check System keychain
echo "Checking System keychain..." | tee -a "${LOG_FILE}"
echo "===== System Keychain =====" >> "${LOG_FILE}"
security list-keychains | grep -q "/Library/Keychains/System.keychain" || {
    echo "Error: System keychain not found" | tee -a "${LOG_FILE}"
    security list-keychains >> "${LOG_FILE}" 2>&1
    exit 1
}
security list-keychains >> "${LOG_FILE}" 2>&1

# Check code-signing identities
echo "Checking code-signing identities..." | tee -a "${LOG_FILE}"
echo "===== Code-signing Identities =====" >> "${LOG_FILE}"
security find-identity -p codesigning -v >> "${LOG_FILE}" 2>&1

# Step 2: Build tests
echo "Building Swift tests..." | tee -a "${LOG_FILE}"
cd "${SWIFT_DIR}"
echo "===== Swift Build Output =====" >> "${LOG_FILE}"
# Ensure the Rust dylib is linked during Swift build so symbols like rn_error_free resolve
swift build --build-tests \
  -Xlinker -L"${RUST_RELEASE_DIR}" \
  -Xlinker -lrunar_ffi >> "${LOG_FILE}" 2>&1 || {
    echo "Error: Swift build failed" | tee -a "${LOG_FILE}"
    exit 1
}

# Step 3: Sign binaries
echo "Signing .xctest bundle without --deep first..." | tee -a "${LOG_FILE}"
echo "===== .xctest Initial Signing Output =====" >> "${LOG_FILE}"
if ! codesign --verbose=4 --force --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${XCTEST_PATH}" >> "${LOG_FILE}" 2>&1; then
    echo "Error: Failed to sign ${XCTEST_PATH} with ad-hoc signing" | tee -a "${LOG_FILE}"
    exit 1
fi

echo "Signing test binary inside .xctest bundle..." | tee -a "${LOG_FILE}"
TEST_BINARY="${XCTEST_PATH}/Contents/MacOS/swift-ffiPackageTests"
if [ -f "${TEST_BINARY}" ]; then
    echo "===== Test Binary Signing Output =====" >> "${LOG_FILE}"
    if ! codesign --verbose=4 --force --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${TEST_BINARY}" >> "${LOG_FILE}" 2>&1; then
        echo "Error: Failed to sign ${TEST_BINARY} with ad-hoc signing" | tee -a "${LOG_FILE}"
        exit 1
    fi
    echo "Success: Test binary signed with get-task-allow entitlement" | tee -a "${LOG_FILE}"
else
    echo "Error: Test binary not found at ${TEST_BINARY}" | tee -a "${LOG_FILE}"
    exit 1
fi

echo "Re-signing .xctest bundle to include signed test binary..." | tee -a "${LOG_FILE}"
echo "===== .xctest Re-signing Output =====" >> "${LOG_FILE}"
if ! codesign --verbose=4 --force --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${XCTEST_PATH}" >> "${LOG_FILE}" 2>&1; then
    echo "Error: Failed to re-sign ${XCTEST_PATH} with ad-hoc signing" | tee -a "${LOG_FILE}"
    exit 1
fi

echo "Signing Rust dylib with ad-hoc signing (using --verbose=4 --options runtime)..." | tee -a "${LOG_FILE}"
echo "===== Rust dylib Signing Output =====" >> "${LOG_FILE}"
if ! codesign --verbose=4 --force --sign - --entitlements "${ENTITLEMENTS}" --options runtime "${DYLIB_PATH}" >> "${LOG_FILE}" 2>&1; then
    echo "Error: Failed to sign ${DYLIB_PATH} with ad-hoc signing" | tee -a "${LOG_FILE}"
    exit 1
fi

# Step 4: Create and Sign Custom debugserver Bundle
echo "Creating custom debugserver bundle..." | tee -a "${LOG_FILE}"
cp "${DEBUGSERVER_ORIG_PATH}" "${CUSTOM_DEBUGSERVER_PATH}"
echo "Signing custom debugserver with ad-hoc signing (using --verbose=4 --options runtime)..." | tee -a "${LOG_FILE}"
echo "===== Custom debugserver Signing Output =====" >> "${LOG_FILE}"
if ! sudo codesign --verbose=4 --force --sign - --entitlements "${DEBUGSERVER_ENTITLEMENTS}" --options runtime "${CUSTOM_DEBUGSERVER_PATH}" >> "${LOG_FILE}" 2>&1; then
    echo "Warning: Failed to sign custom debugserver with ad-hoc signing" | tee -a "${LOG_FILE}"
else
    echo "Success: custom debugserver signed with ad-hoc signing" | tee -a "${LOG_FILE}"
fi


# Step 5: Verify signatures (for logging, not fatal)
echo "Verifying test binary signature..." | tee -a "${LOG_FILE}"
echo "===== Test Binary Signature Verification =====" >> "${LOG_FILE}"
if [ -f "${TEST_BINARY}" ]; then
    codesign -dv --entitlements :- "${TEST_BINARY}" >> "${LOG_FILE}" 2>&1
    if grep -q "com.apple.security.get-task-allow.*true" "${LOG_FILE}"; then
        echo "Success: Test binary has get-task-allow entitlement" | tee -a "${LOG_FILE}"
    else
        echo "Warning: Test binary missing get-task-allow entitlement" | tee -a "${LOG_FILE}"
    fi
else
    echo "Warning: Test binary not found for verification" | tee -a "${LOG_FILE}"
fi

echo "Verifying .xctest bundle signature..." | tee -a "${LOG_FILE}"
echo "===== .xctest Signature Verification =====" >> "${LOG_FILE}"
codesign -dv --entitlements :- "${XCTEST_PATH}" >> "${LOG_FILE}" 2>&1
if grep -q "com.apple.security.get-task-allow.*true" "${LOG_FILE}"; then
    echo "Success: .xctest bundle has get-task-allow entitlement" | tee -a "${LOG_FILE}"
else
    echo "Warning: .xctest bundle missing get-task-allow entitlement" | tee -a "${LOG_FILE}"
fi


echo "Verifying Rust dylib signature..." | tee -a "${LOG_FILE}"
echo "===== Rust dylib Signature Verification =====" >> "${LOG_FILE}"
codesign -dv --entitlements :- "${DYLIB_PATH}" >> "${LOG_FILE}" 2>&1
if grep -q "com.apple.security.get-task-allow.*true" "${LOG_FILE}"; then
    echo "Success: Rust dylib has get-task-allow entitlement" | tee -a "${LOG_FILE}"
else
    echo "Warning: Rust dylib missing get-task-allow entitlement" | tee -a "${LOG_FILE}"
fi

echo "Verifying custom debugserver signature..." | tee -a "${LOG_FILE}"
echo "===== Custom debugserver Signature Verification =====" >> "${LOG_FILE}"
codesign -dv --entitlements :- "${CUSTOM_DEBUGSERVER_PATH}" >> "${LOG_FILE}" 2>&1
if grep -q "com.apple.security.cs.debugger.*true" "${LOG_FILE}"; then
    echo "Success: custom debugserver has cs.debugger entitlement" | tee -a "${LOG_FILE}"
else
    echo "Warning: custom debugserver missing cs.debugger entitlement" | tee -a "${LOG_FILE}"
fi


# Step 6: Check SIP status
echo "Checking SIP status..." | tee -a "${LOG_FILE}"
echo "===== SIP Status =====" >> "${LOG_FILE}"
csrutil status >> "${LOG_FILE}" 2>&1
if grep -q "enabled" "${LOG_FILE}" && ! grep -q "Debugging Restrictions: disabled" "${LOG_FILE}"; then
    echo "Warning: SIP debugging restrictions are enabled. If attach fails, consider disabling:" | tee -a "${LOG_FILE}"
    echo "  Boot to Recovery Mode and run: csrutil enable --without debug" | tee -a "${LOG_FILE}"
fi


# Step 7: Run LLDB test with proper crash handling
echo "Running LLDB test..." | tee -a "${LOG_FILE}"
echo "===== LLDB Output =====" >> "${LOG_FILE}"
export DYLD_LIBRARY_PATH="${RUST_RELEASE_DIR}:${RUST_RELEASE_DIR}/deps"
export LLDB_DEBUGSERVER_PATH="${CUSTOM_DEBUGSERVER_PATH}"

# Create LLDB script for better crash handling
cat > /tmp/lldb_script.lldb << 'EOF'
settings set target.env-vars DYLD_LIBRARY_PATH=/Users/rafael/dev/runar-swift/runar-rust/target/debug:/Users/rafael/dev/runar-swift/runar-rust/target/debug/deps RUST_LOG=trace RUST_BACKTRACE=1
log enable lldb break process thread unwind
breakpoint set --name main
# Also break on Swift CAClient.enroll entry to capture a backtrace near the call site
breakpoint set --file SwiftFFI.swift --line 3437
# Break at the Rust FFI entry for enroll
breakpoint set --name rn_transport_ca_client_enroll
process handle SIGSEGV --notify true --stop true --pass false
process handle SIGBUS --notify true --stop true --pass false
process handle EXC_BAD_ACCESS --notify true --stop true --pass false
run
# On stop, dump useful diagnostics
thread backtrace all
register read
memory read --size 8 --format x --count 32 $pc-128
image list
image lookup --address $pc
EOF

# Run LLDB with the script
lldb --batch -s /tmp/lldb_script.lldb -- "${XCTEST_PATH}/Contents/MacOS/swift-ffiPackageTests" >> "${LOG_FILE}" 2>&1 || true


# Step 8: Check for attach failure or crash
if grep -q "attach failed" "${LOG_FILE}"; then
    echo "Error: LLDB attach failed. Capturing debugserver logs..." | tee -a "${LOG_FILE}"
    echo "===== Debugserver System Logs =====" >> "${LOG_FILE}"
    log show --predicate '(subsystem == "com.apple.debugserver") || (process == "debugserver") || (subsystem CONTAINS "AppleMobileFileIntegrity")' --style syslog --info --debug --last 60m | grep -i 'error\|denied\|failed\|tainted' >> "${LOG_FILE}" 2>&1
    if grep -q "error\|denied\|failed\|tainted" "${LOG_FILE}"; then
        echo "Debugserver logs captured in ${LOG_FILE}" | tee -a "${LOG_FILE}"
    else
        echo "No debugserver logs found. Check Console.app for 'debugserver' or 'AppleMobileFileIntegrity' messages around $(date)." | tee -a "${LOG_FILE}"
    fi
    echo "Suggestions:" | tee -a "${LOG_FILE}"
    echo "1. Install full Xcode from the App Store." | tee -a "${LOG_FILE}"
    echo "2. Check for macOS updates or known codesigning bugs." | tee -a "${LOG_FILE}"
    exit 1
elif grep -q "EXC_BREAKPOINT\|SIGSEGV" "${LOG_FILE}"; then
    echo "Error: Process crashed with EXC_BREAKPOINT or SIGSEGV. Check ${LOG_FILE} for stack trace." | tee -a "${LOG_FILE}"
    echo "===== Debugserver System Logs =====" >> "${LOG_FILE}"
    log show --predicate '(subsystem == "com.apple.debugserver") || (process == "debugserver") || (subsystem CONTAINS "AppleMobileFileIntegrity")' --style syslog --info --debug --last 60m | grep -i 'error\|denied\|failed\|tainted' >> "${LOG_FILE}" 2>&1
    if grep -q "error\|denied\|failed\|tainted" "${LOG_FILE}"; then
        echo "Debugserver logs captured in ${LOG_FILE}" | tee -a "${LOG_FILE}"
    else
        echo "No debugserver logs found. Check Console.app for 'debugserver' or 'AppleMobileFileIntegrity' messages around $(date)." | tee -a "${LOG_FILE}"
    fi
fi

echo "Test execution completed. Check ${LOG_FILE} for stack trace if signal 11 occurred." | tee -a "${LOG_FILE}"