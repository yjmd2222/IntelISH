// SPDX-License-Identifier: GPL-2.0-only
#include "../IntelISH/AccelerometerReport.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
int main(int argc, char **argv) {
    assert(argc == 2); FILE *f = fopen(argv[1], "rb"); assert(f);
    unsigned char descriptor[4096]; unsigned length = fread(descriptor,1,sizeof(descriptor),f); fclose(f);
    ISHAccel::Layout l; assert(ISHAccel::parse(descriptor,length,l));
    assert(l.report==7 && l.featureBytes==229 && l.inputBytes==32);
    assert(l.power.enabledValue==2 && l.reporting.enabledValue==2);
    for(unsigned i=0;i<3;i++) { assert(l.axes[i].bit==152+32*i && l.axes[i].width==32); assert(l.axes[i].exponent==-6 && l.axes[i].unit==0); }
    std::vector<unsigned char> feature(l.featureBytes,0xa5); feature[0]=7; auto original=feature;
    assert(ISHALS::insert(feature.data(),feature.size(),l.power,2));
    assert(ISHALS::insert(feature.data(),feature.size(),l.reporting,2));
    for(unsigned bit=0;bit<feature.size()*8;bit++) {
        if((bit>=l.power.bit && bit<l.power.bit+l.power.width)||(bit>=l.reporting.bit && bit<l.reporting.bit+l.reporting.width))continue;
        assert(!((feature[bit/8]^original[bit/8])&(1U<<(bit%8))));
    }
    auto m=ISHAccel::motionLayout(l); assert(motion::valid(m));
    std::vector<unsigned char> input(l.inputBytes);input[0]=7;
    int64_t expected[3]={-1000000,250000,INT32_MIN};
    for(unsigned axis=0;axis<3;axis++) {
        uint32_t raw=static_cast<uint32_t>(expected[axis]);
        for(unsigned bit=0;bit<32;bit++) if(raw&(1U<<bit)) input[(l.axes[axis].bit+bit)/8]|=1U<<((l.axes[axis].bit+bit)%8);
    }
    motion::Sample sample;assert(motion::decode(m,input.data(),input.size(),123,sample)==motion::Result::OK);
    for(unsigned i=0;i<3;i++)assert(sample.axes[i]==expected[i]);assert(sample.timestampNS==123);
    for(unsigned n=0;n<input.size();n++)assert(motion::decode(m,input.data(),n,0,sample)==motion::Result::Truncated);
    input[0]=5;assert(motion::decode(m,input.data(),input.size(),0,sample)==motion::Result::WrongReport);
    for(unsigned n=0;n<length;n++){ISHAccel::Layout truncated;assert(!ISHAccel::parse(descriptor,n,truncated));}
    unsigned seed=17;for(unsigned i=0;i<10000;i++){unsigned char fuzz[256];for(auto &b:fuzz){seed=seed*1664525+1013904223;b=seed>>24;}ISHAccel::Layout parsed;ISHAccel::parse(fuzz,sizeof(fuzz),parsed);}
    printf("Accelerometer descriptor, signed decoding, control preservation and malformed-report checks passed\n");
}
