module base.d.base64;

import std.range.primitives : ElementType, isInputRange, isInfinite;
import std.range.primitives : front, popFront, empty;
import std.utf : front, popFront, empty;

//Sadly not available in std.traits
enum isExplicitlyConvertible(From, To) = __traits(compiles, cast(To) From.init);

struct Base64Encoder(Range)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    static immutable encodingChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

    private Range range;
    private ubyte oldValue;
    private ubyte pos;

    this(Range range)
    {
        this.range = range;
    }

    immutable(char) front()
    {
        //Signals padding is required
        if(range.empty && !oldValue)
            return encodingChars[$-1];

        ubyte newValue = range.empty? 0 : cast(ubyte)range.front;

        //pos is guaranteed to be in [0, 4)
        final switch(pos)
        {
            case 0: return encodingChars[(newValue & 0xfc) >> 2];
            case 1: return encodingChars[((oldValue & 0x03) << 4) | ((newValue & 0xf0) >> 4)];
            case 2: return encodingChars[((oldValue & 0x0f) << 2)|((newValue & 0xc0) >> 6)];
            case 3: return encodingChars[oldValue & 0x3f];
        }
    }

    void popFront()
    {
        //Ensure that pos remains in [0, 4)
        pos = (pos + 1) & 3;

        oldValue = range.empty? 0 : cast(ubyte)range.front;
        if(!range.empty && pos != 0)
            range.popFront;
    }

    bool empty()
    {
        //Data is all consumed, and padding is done
        return range.empty && !pos;
    }
}

auto base64Encode(Range)(Range r)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    return Base64Encoder!Range(r);
}

unittest
{
    import std.algorithm : equal;
    import std.base64 : Base64;
    import std.utf : byChar;

    assert("test string".byChar.base64Encode.equal(Base64.encode(cast(ubyte[])"test string")));
    assert("test strin" .byChar.base64Encode.equal(Base64.encode(cast(ubyte[])"test strin")));
    assert("test stri"  .byChar.base64Encode.equal(Base64.encode(cast(ubyte[])"test stri")));

    assert("mary had a little lamb".byChar.base64Encode.equal("bWFyeSBoYWQgYSBsaXR0bGUgbGFtYg=="));
    assert("MARY HAD A LITTLE LAMB".byChar.base64Encode.equal("TUFSWSBIQUQgQSBMSVRUTEUgTEFNQg=="));
}

unittest
{
    //Test bulk data
    import std.string : succ;
    import std.algorithm : equal;
    import std.utf : byChar;
    import std.base64 : Base64;

    string s = "0";
    foreach(_; 0..1000)
    {
        //Anything encoded then decoded should be itself
        assert(s.byChar.base64Encode.equal(Base64.encode(cast(ubyte[])s)));
        //Generate the next string
        s = s.succ;
    }

}

struct Base64Decoder(Range)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, char))
{
    static immutable encodingChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

    private Range range;
    private ubyte oldValue;
    private ubyte pos;

    this(Range range)
    {
        this.range = range;
        if(!range.empty)
        {
            oldValue = this.range.front;
            this.range.popFront;
        }
    }

    ubyte front()
    {
        import std.string : indexOf;

        auto oldIndex = cast(ubyte)(oldValue == '='?0 : encodingChars.indexOf(oldValue));
        auto newIndex = cast(ubyte)(range.front == '='? 0 : encodingChars.indexOf(range.front));

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
        if(!pos)
        {
            range.popFront;
            //We may or may not have another chunk of data to deal with
            if(!range.empty)
            {
                oldValue = range.front;
                range.popFront;
            }
        }
        else
        {
            oldValue = range.front;
            range.popFront;
        }
    }

    bool empty()
    {
        return range.empty || range.front == '=';
    }
}

auto base64Decode(Range)(Range r)
    if(isInputRange!Range &&
       isExplicitlyConvertible!(ElementType!Range, ubyte))
{
    return Base64Decoder!Range(r);
}

unittest
{
    import std.algorithm : equal;
    import std.base64 : Base64;
    import std.utf : byChar;
    import std.range : walkLength;

    assert("dGVzdCBzdHJpbmc=".byChar.base64Decode.equal(Base64.decode(cast(ubyte[])"dGVzdCBzdHJpbmc=")));
    assert("dGVzdCBzdHJpbg==".byChar.base64Decode.equal(Base64.decode(cast(ubyte[])"dGVzdCBzdHJpbg==")));
    assert("dGVzdCBzdHJp"  .byChar.base64Decode.equal(Base64.decode(cast(ubyte[])"dGVzdCBzdHJp")));
}

//Both in unison
unittest
{
    import std.string : succ;
    import std.algorithm : equal;
    import std.utf : byChar;

    string s = "0";
    foreach(_; 0..1000)
    {
        //Anything encoded then decoded should be itself
        assert(s.byChar.base64Encode.base64Decode.equal(s));
        //Generate the next string
        s = s.succ;
    }
}
