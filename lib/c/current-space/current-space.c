/*
 * current-space.c
 *
 * Get the current macOS Mission Control space ID.
 * Uses private CoreGraphics APIs to query the window server.
 *
 * Returns: Space ID on stdout
 *
 * Note: This returns the internal space ID, not the human-readable number.
 * Use the shell wrapper in bin/current-space to get the Mission Control number.
 */

#include <stdio.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>

// Private CoreGraphics API Types
typedef int CGSConnection;
typedef uint64_t CGSSpaceID;

// Private API Function Declarations
extern CGSConnection _CGSDefaultConnection(void);
extern CGSSpaceID CGSGetActiveSpace(CGSConnection cid);

int main(void) {
    // Get connection to the window server
    CGSConnection conn = _CGSDefaultConnection();
    if (!conn) {
        fprintf(stderr, "Error: Could not connect to window server\n");
        return 1;
    }

    // Get the current active space ID
    CGSSpaceID activeSpace = CGSGetActiveSpace(conn);
    if (!activeSpace) {
        fprintf(stderr, "Error: Could not get active space\n");
        return 1;
    }

    // Output just the space ID
    printf("%llu\n", activeSpace);

    return 0;
}
