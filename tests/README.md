# Tests

Standalone host tests for the protocol and ALS code. They are not part of the kext build.
Run from the project root; both use ASan/UBSan.

```sh
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined tests/protocol-tests.cpp -o /tmp/ish-protocol-tests
/tmp/ish-protocol-tests
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined tests/als-tests.cpp -o /tmp/ish-als-tests
/tmp/ish-als-tests tests/test-data/device0-20261005.bin
```

- `protocol-tests.cpp`: ISH packet routing, headers and fragmented reassembly.
- `als-tests.cpp`: ALS descriptor parsing, field preservation, scaling and malformed data.
- `test-data/device0-20261005.bin`: HID report descriptor captured from this machine's ISH device 0 (Capella CM32181 ALS).
