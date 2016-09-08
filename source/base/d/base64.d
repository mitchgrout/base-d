module base.d.base64;

import std.range.primitives;
import std.utf : front, popFront, empty;


//Not available in std.traits
enum isExplicitlyConvertible(From, To) = __traits(compiles, cast(To) From.init);


///Programmatically generates a ubyte[128] table
///As per the standard, the extra characters must be in the
///US-ASCII character set, and thus must have values < 128
template makeTable(char char62, char char63, char padding)
    if(char62 < 128 && char63 < 128 && padding < 128)
{
    auto make()
    {
        ubyte[128] encodingChars = ubyte.max;

        foreach(i, c; "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
            encodingChars[c] = cast(ubyte)i;

        //Manually fill the rest of the table
        encodingChars[char62] = 62;
        encodingChars[char63] = 63;
        encodingChars[padding] = 0;

        return encodingChars;
    }

    enum makeTable = make();
}


///Lazily encodes a given Range to base64. The range must be an input range
///whose element type is castable to a ubyte.
struct Base64Encoder(Range)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    //TODO: Allow the final three chars to be decidable by the user
    static immutable encodingChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

    private Range range;
    private ubyte oldValue;
    private ubyte pos;
    private bool paddingRequired;

    this(Range range)
    {
        this.range = range;
    }

    immutable(char) front()
    {
        assert(!empty, "Cannot call front() on an empty range");

        //Signals padding is required
        if(range.empty && paddingRequired)
            return encodingChars[$-1];

        ubyte newValue = range.empty? 0 : cast(ubyte)range.front;
        size_t index;

        //pos is guaranteed to be in [0, 4)
        final switch(pos)
        {
            case 0: index = (newValue & 0xfc) >> 2; break;
            case 1: index = ((oldValue & 0x03) << 4) | ((newValue & 0xf0) >> 4); break;
            case 2: index = ((oldValue & 0x0f) << 2)|((newValue & 0xc0) >> 6); break;
            case 3: index = oldValue & 0x3f; break;
        }

        //Bounds-check
        assert(index < encodingChars.length, "Encoded index was out of bounds");

        return encodingChars[index];
    }

    void popFront()
    {
        assert(!empty, "Cannot call popFront() on an empty range");

        //Ensure that pos remains in [0, 4)
        pos = (pos + 1) & 3;

        if(range.empty)
        {
            paddingRequired = true;
            oldValue = 0;
        }
        else
            oldValue = cast(ubyte)range.front;

        //Since encoding is 3:4 bytes, we need to pop the underlying range
        //3 times while still producing 4 values
        if(!range.empty && pos != 0)
            range.popFront;
    }

    bool empty()
    {
        //Data is all consumed, and padding is done
        return range.empty && !pos;
    }

    static if(isForwardRange!Range)
    typeof(this) save()
    {
        typeof(this) res = this;
        res.range = res.range.save;
        return res;
    }
}


///Ditto
auto base64Encode(Range)(Range r)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    return Base64Encoder!Range(r);
}


///
pure @safe unittest
{
    import std.algorithm : equal;
    import std.base64 : Base64;
    import std.utf : byChar;

    assert("test string".byChar.base64Encode.equal("dGVzdCBzdHJpbmc="));
    assert("test strin" .byChar.base64Encode.equal("dGVzdCBzdHJpbg=="));
    assert("test stri"  .byChar.base64Encode.equal("dGVzdCBzdHJp"));

    assert("123456789".byChar.base64Encode.equal("MTIzNDU2Nzg5"));
    assert("234567891".byChar.base64Encode.equal("MjM0NTY3ODkx"));
    assert("345678912".byChar.base64Encode.equal("MzQ1Njc4OTEy"));

    assert("".byChar.base64Encode.equal(""));
}


pure @safe unittest
{
    import std.algorithm : equal;
    import std.utf : byChar;

    assert("Input string".byChar.base64Encode.equal("SW5wdXQgc3RyaW5n"));
    assert("Input strin" .byChar.base64Encode.equal("SW5wdXQgc3RyaW4="));
    assert("Input stri"  .byChar.base64Encode.equal("SW5wdXQgc3RyaQ=="));
}


pure nothrow @safe @nogc unittest
{
    //Edge case: This should encode to 'AAAAAAAA'
    ubyte[6] data = [0,0,0,0,0,0];
    size_t i;
    foreach(c; data[].base64Encode)
    {
        assert(c == 'A');
        i++;
    }
    assert(i == 8);
}


///Lazily decodes a given base64 encoded Range. The range must be an input range
///whose element type is castable to a ubyte.
struct Base64Decoder(Range)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, char))
{
    static immutable encodingChars = makeTable!('+', '/', '=');

    private Range range;
    private ubyte oldValue;
    private ubyte pos;

    this(Range range)
    {
        this.range = range;

        //Decoding is 4:3, so we immediately skip the first item
        if(!range.empty)
        {
            oldValue = cast(ubyte)this.range.front;
            this.range.popFront;
        }
    }

    ubyte front()
    {
        assert(!empty, "Cannot call front() on an empty range");

        //Bounds-check
        assert(oldValue < encodingChars.length);
        assert((cast(ubyte)range.front) < encodingChars.length);

        auto oldIndex = encodingChars[oldValue];
        auto newIndex = encodingChars[range.front];

        assert(oldIndex != ubyte.max && newIndex != ubyte.max, "Read invalid base64 character");

        final switch(pos)
        {
            case 0: return cast(ubyte)((oldIndex << 2) | (newIndex >> 4));
            case 1: return cast(ubyte)((oldIndex << 4) | (newIndex >> 2));
            case 2: return cast(ubyte)((oldIndex << 6) | newIndex);
        }
    }

    void popFront()
    {
        assert(!range.empty, "Cannot popFront() an empty range");

        pos = (pos+1) % 3;
        //If we're in position zero, we need to skip to the next one
        //as our decoding is 4:3
        if(!pos)
        {
            range.popFront;
            //We may or may not have another chunk of data to deal with
            if(!range.empty)
            {
                oldValue = cast(ubyte)range.front;
                range.popFront;
            }
        }
        else
        {
            oldValue = cast(ubyte)range.front;
            range.popFront;
        }
    }

    bool empty()
    {
        //Final padding can be ignored
        return range.empty || range.front == '=';
    }

    static if(isForwardRange!Range)
    typeof(this) save()
    {
        typeof(this) res = this;
        res.range = res.range.save;
        return res;
    }
}


///Ditto
auto base64Decode(Range)(Range r)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    return Base64Decoder!Range(r);
}


///
pure @safe unittest
{
    import std.algorithm : equal;
    import std.base64 : Base64;
    import std.utf : byChar;
    import std.range : walkLength;

    assert("dGVzdCBzdHJpbmc=".byChar.base64Decode.equal("test string"));
    assert("dGVzdCBzdHJpbg==".byChar.base64Decode.equal("test strin"));
    assert("dGVzdCBzdHJp"    .byChar.base64Decode.equal("test stri"));
}


pure nothrow @safe @nogc unittest
{
    //Base-bones decoding should be pure/nothrow/safe/nogc
    import std.utf : byChar;
    char[8] data = 'A';
    size_t i;
    foreach(c; data[].byChar.base64Decode)
    {
        assert(c == 0);
        i++;
    }
    assert(i == 6);
}


pure unittest
{
    import std.exception : assertThrown, assertNotThrown;
    import core.exception : AssertError;

    //Calls {empty|front|popFront} until the range is consumed
    void consume(Range)(Range r)
    {
        foreach(_; r) { }
    }

    assertThrown!AssertError(consume("some bad string!".base64Decode));
    assertNotThrown!AssertError(consume("validstring=".base64Decode));
}


pure @safe unittest
{
    import std.string : succ;
    import std.algorithm : equal;
    import std.utf : byChar;

    string s = "0";
    foreach(_; 0 .. 10000)
    {
        //Anything encoded then decoded should be itself
        assert(s.byChar.base64Encode.base64Decode.equal(s));
        //Generate the next string
        s = s.succ;
    }
}


//Determines whether a given range represents a valid base64 string
bool isValidBase64(Range)(Range r)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, char))
{
    static immutable encodingChars = makeTable!('+', '/', '=');
    size_t count;
    size_t padding;

    foreach(val; r)
    {
        auto index = cast(char)val;

        count++;
        if(index == '=')
            padding++;

        //Found an invalid character in our input, found a non-padding char
        //after we began padding, or found more than the allowable number of padding chars
        if(encodingChars[index] == ubyte.max ||
           (padding && index != '=') ||
           (padding > 2 && index == '='))
        {
            return false;
        }
    }

    //Our input is now valid iff we encountered an even number of 4-chars
    return !(count & 3);
}


pure nothrow @safe @nogc unittest
{
    assert(!isValidBase64("invalid due to invalid chars"));
    assert(!isValidBase64("badlength"));
    assert(!isValidBase64("bad=padding"));
    assert(!isValidBase64("worse==padding"));
    assert(!isValidBase64("the============worst"));
    assert(!isValidBase64("stillbad===="));
    assert(!isValidBase64("=="));

    assert(isValidBase64(""));
    assert(isValidBase64("validstring="));
    assert(isValidBase64("data"));
    assert(isValidBase64("dGVzdAo="));
}


pure @safe unittest
{
    import std.string : succ;
    import std.algorithm : equal;
    import std.utf : byChar;

    string s = "0";
    foreach(_; 0 .. 10000)
    {
        assert(isValidBase64(s.base64Encode));
        //Generate the next string
        s = s.succ;
    }
}
