// SPDX-License-Identifier: GPL-2.0-only
#include "ALSReport.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
int main(int argc, char **argv) {
    assert(argc == 2);
    FILE *file = std::fopen(argv[1], "rb"); assert(file);
    unsigned char descriptor[4096]; unsigned size = std::fread(descriptor, 1, sizeof(descriptor), file);
    std::fclose(file);
    ISHALS::Layout layout;
    assert(ISHALS::parse(descriptor, size, layout));
    std::printf("ALS report=%u featureBytes=%u inputBytes=%u power=%u/%u value=%u reporting=%u/%u value=%u interval=%u/%u illum=%u/%u exp=%d unit=%u\n",
        layout.report,layout.featureBytes,layout.inputBytes,layout.power.bit,layout.power.width,layout.power.enabledValue,
        layout.reporting.bit,layout.reporting.width,layout.reporting.enabledValue,layout.interval.bit,layout.interval.width,
        layout.illuminance.bit,layout.illuminance.width,layout.illuminance.exponent,layout.illuminance.unit);
    assert(layout.report == 2 && layout.power.enabledValue == 2 && layout.reporting.enabledValue == 2);
    std::vector<unsigned char> feature(layout.featureBytes, 0xa5); feature[0]=2;
    auto original=feature;
    assert(ISHALS::insert(feature.data(), feature.size(), layout.power, 2));
    assert(ISHALS::insert(feature.data(), feature.size(), layout.reporting, 2));
    for(unsigned bit=0;bit<feature.size()*8;++bit) {
        if ((bit>=layout.power.bit && bit<layout.power.bit+layout.power.width) ||
            (bit>=layout.reporting.bit && bit<layout.reporting.bit+layout.reporting.width)) continue;
        assert(((feature[bit/8]^original[bit/8]) & (1U<<(bit%8))) == 0);
    }
    assert(!ISHALS::insert(feature.data(),feature.size(),layout.power,255));
    std::vector<unsigned char> input(layout.inputBytes);input[0]=2;
    assert(ISHALS::insert(input.data(),input.size(),layout.illuminance,5000));
    unsigned long long value=0;
    assert(ISHALS::milliLux(input.data(),input.size(),layout,value) && value==5000);
    assert(!ISHALS::milliLux(input.data(),input.size()-1,layout,value));
    // Exact GET_INPUT payload from logs/ish-20261005-134631.txt.
    const unsigned char observed[] = {0x02,0x02,0x05,0x80,0xa0,0x37,0x02,0x00,
        0x00,0x00,0x00,0x00,0x45,0x2c,0x16,0x00,0x00,0x00,0x00,0xb5,0x54,0x00,0x00};
    assert(ISHALS::milliLux(observed,sizeof(observed),layout,value) && value==21685);
    assert(layout.illuminance.maximum == 10000);
    assert(!ISHALS::milliLux(observed,sizeof(observed)-1,layout,value));
    input[0]=3;assert(!ISHALS::milliLux(input.data(),input.size(),layout,value));
    for(unsigned n=0;n<size;++n) { ISHALS::Layout shortLayout;assert(!ISHALS::parse(descriptor,n,shortLayout)); }
    unsigned seed=2;
    for(unsigned n=0;n<10000;++n) {
        unsigned char fuzz[256];
        for(auto &b:fuzz){seed=seed*1664525U+1013904223U;b=seed>>24;}
        ISHALS::Layout randomLayout;(void)ISHALS::parse(fuzz,n%256,randomLayout);
    }
    std::puts("ALS descriptor, field preservation, scaling and malformed-data tests passed");
}
