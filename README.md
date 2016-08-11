# base-d
A simple library for encoding and decoding base64

Unlike `std.base64`, this library aims to do encoding and decoding in a lazy fashion.
Of course, this means `base-d` will be slightly slower than the eager `std.base64`, but will operate without having to allocate any memory.

###TODO:
- Implement base32
- Improve documentation
- Add more tests
