// SPDX-License-Identifier: GPL-2.0-only
#include "../Protocol.hpp"
#include <cassert>
#include <cstdio>
#include <cstring>
using namespace ISHProtocol;
int main() {
    // The formerly rejected nonzero-address packet is structurally valid ISHTP.
    unsigned char fixed[16] = {13, 0, 12, 0x80, 1};
    Header h {};
    assert(parse(fixed, sizeof(fixed), h));
    assert(h.firmware == 13 && h.host == 0 && h.complete && h.length == 12);
    unsigned char fragment[128] = {3, 1, 124, 0};
    assert(parse(fragment, sizeof(fragment), h) && !h.complete && h.host == 1);
    fragment[3] = 0x82; // Reserved bit must not pass validation.
    assert(!parse(fragment, sizeof(fragment), h));
    fragment[3] = 0x80; fragment[2] = 123;
    assert(!parse(fragment, sizeof(fragment), h));
    assert(!parse(nullptr, 128, h));
    assert(!parse(fixed, 3, h));
    assert(!parse(fragment, 129, h));
    // Reassemble a full 4096-byte response, with non-aligned last fragment.
    Assembly a;
    unsigned char payload[124];
    unsigned offset = 0;
    while (offset < 4096) {
        unsigned n = 4096 - offset < 124 ? 4096 - offset : 124;
        for (unsigned i = 0; i < n; ++i) payload[i] = (offset + i) & 255;
        assert(a.append(payload, n, 4096)); offset += n;
    }
    for (unsigned i = 0; i < 4096; ++i) assert(a.bytes[i] == (i & 255));
    assert(!a.append(payload, 1, 4096) && a.used == 4096);
    assert(!a.append(payload, 0, 4095));
    a.used = 0;
    assert(!a.append(payload, 124, 123) && a.used == 0);
    assert(!a.append(payload, 1, 4097));
    assert(!a.append(nullptr, 0, 4096));
    // Sweep truncated/random mailbox lengths; sanitizer checks all reads.
    unsigned seed = 0x3312;
    for (unsigned iteration = 0; iteration < 100000; ++iteration) {
        unsigned char packet[128];
        for (auto &b : packet) { seed = seed * 1664525U + 1013904223U; b = seed >> 24; }
        unsigned size = iteration % 129;
        if (parse(packet, size, h)) {
            assert(size >= 4 && h.length == size - 4);
            assert(!(little32(packet) & 0x7e000000U));
        }
    }
    std::puts("ISH packet routing/header and fragmented reassembly tests passed");
}
