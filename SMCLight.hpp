// Light key format adapted from VirtualSMC SMCLightSensor (usrsse2, 2018).
// VirtualSMC-derived portions: BSD-3-Clause; see VirtualSMC-LICENSE.txt.
#pragma once
#include <VirtualSMCSDK/kern_vsmcapi.hpp>
static_assert(SMC_MAKE_IDENTIFIER('A','L','V','0') == 0x30564c41U, "VirtualSMC key byte order");
class ISHForceBits : public VirtualSMCValue {
public: uint8_t bits() const { return data[0]; }
};
class ISHLightValue : public VirtualSMCValue {
    _Atomic(uint32_t) *fixedLux;
    ISHForceBits *force;
protected:
    SMC_RESULT readAccess() override {
        uint32_t lux = atomic_load_explicit(fixedLux, memory_order_acquire);
        data[0] = lux != UINT32_MAX;
        if (lux != UINT32_MAX) {
            uint8_t bits = force->bits();
            if (!(bits & 8)) data[1] = 1;
            if (!(bits & 2)) OSWriteBigInt16(data, 2, static_cast<uint16_t>(lux >> 14));
            if (!(bits & 4)) OSWriteBigInt32(data, 6, lux);
        }
        return SmcSuccess;
    }
public:
    ISHLightValue(_Atomic(uint32_t) *value, ISHForceBits *bits) : fixedLux(value), force(bits) {}
};
