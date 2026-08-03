#include "../haptic_bridge.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

int main(void) {
    assert(gfn_map_rumble_level(-1) == 0);
    assert(gfn_map_rumble_level(0) == 0);
    assert(gfn_map_rumble_level(1) == 257);
    assert(gfn_map_rumble_level(30) == 7710);
    assert(gfn_map_rumble_level(128) == 32896);
    assert(gfn_map_rumble_level(255) == UINT16_MAX);
    assert(gfn_map_rumble_level(256) == UINT16_MAX);

    uint8_t actual[GFN_TRITON_RUMBLE_REPORT_SIZE];
    const uint8_t expected[GFN_TRITON_RUMBLE_REPORT_SIZE] = {
        0x80, 0x00, 0x00, 0x00, 0x34,
        0x12, 0x00, 0xcd, 0xab, 0x00,
    };
    gfn_build_triton_rumble_report(0x1234, 0xabcd, actual);
    assert(memcmp(actual, expected, sizeof(expected)) == 0);

    assert(gfn_test_next_rumble_wait_ms(100, 100, 1000) == 40);
    assert(gfn_test_next_rumble_wait_ms(139, 100, 1000) == 1);
    assert(gfn_test_next_rumble_wait_ms(140, 100, 1000) == 0);
    assert(gfn_test_next_rumble_wait_ms(100, 100, 130) == 30);
    assert(gfn_test_next_rumble_wait_ms(131, 100, 130) == 0);
    return 0;
}
