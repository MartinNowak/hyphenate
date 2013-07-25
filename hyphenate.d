import std.algorithm, std.conv, std.range;
import std.ascii : isDigit;
import std.uni : toLower;
import std.stdio, std.traits;
import core.bitop;

enum HYPHEN = "&shy;";
//enum HYPHEN = "-";

struct BitArray
{
    this(R)(in R data) if (isIntegral!(ElementType!R))
    {
        _bits = encode(data);
    }

    @property bool empty() const
    {
        return _bits == fillBits;
    }

    @property ubyte front() const
    in { assert(!empty); }
    body
    {
        return cast(ubyte)((!!(_bits & 1) ? bsf(~_bits) : bsf(_bits)) - 1);
    }

    void popFront()
    {
        immutable shift = front + 1;
        _bits = _bits >> shift | fillBits << 32 - shift;
    }

private:
    uint encode(R)(in R data)
    in { assert(reduce!"a+b"(0, data) + data.length < 32, data.to!string()); }
    body
    {
        uint res = fillBits;
        size_t i;
        foreach (val; data.retro())
        {
            res <<= val + 1;
            if (i++ & 1) res |= (1 << val + 1) - 1;
        }
        return res;
    }

    enum fillBits = uint.max;
    uint _bits = fillBits;
}

unittest
{
    foreach (val; BitArray([14, 15]))
    {}

    foreach (data; [[0], [0, 1, 0], [30], [14, 15], [0, 13, 13, 0, 0]])
        assert(equal(BitArray(data), data));
}

alias Priorities = BitArray;

@property auto letters(string s) { return s.filter!(a => !a.isDigit())(); }
@property Priorities priorities(R)(R r)
{
    ubyte buf[20] = void;
    size_t pos = 0;
    while (!r.empty)
    {
        immutable c = r.front; r.popFront();
        if (c.isDigit())
        {
            buf[pos++] = cast(ubyte)(c - '0');
            if (!r.empty) r.popFront();
        }
        else
        {
            buf[pos++] = 0;
        }
    }
    while (pos && buf[pos-1] == 0)
        --pos;
    return Priorities(buf[0 .. pos]);
}


extern(C) void* _aaGetX(void** pp, const TypeInfo keyti, in size_t valuesize, void* pkey);

@property ref V getLvalue(AA : V[K], K, V)(ref AA aa, K key)
{
    return *cast(V*)_aaGetX(cast(void**)&aa, typeid(K), V.sizeof, &key);
}

unittest
{
    enum testcases = [
        "a1bc3d4" : [0, 1, 0, 3, 4],
        "to2gr" : [0, 0, 2],
        "1to" : [1],
        "x3c2" : [0, 3, 2],
        "1a2b3c4" : [1, 2, 3, 4],
    ];
    foreach (pat, prios; testcases)
        assert(equal(priorities(pat), prios));
}

struct Trie
{
    this(dchar c)
    {
        debug _c = c;
    }

    static struct Table
    {
        inout(Trie)* opIn_r(dchar c) inout
        {
            if (c >= 128 || !bt(bitmaskPtr, c))
                return null;
            return &entries[getPos(c)-1];
        }

        ref Trie getLvalue(dchar c)
        {
            if (c >= 128) assert(0);
            auto npos = getPos(c);
            if (!bts(bitmaskPtr, c))
                entries.insertInPlace(npos++, Trie(c));
            return entries[npos-1];
        }

        private size_t getPos(dchar c) const
        {
            immutable nbyte = c / 32; c &= 31;
            size_t npos;
            foreach (i; 0 .. nbyte)
                npos += popcnt(bitmask[i]);
            npos += popcnt(bitmask[nbyte] & (1 << c | (1 << c) - 1));
            return npos;
        }

        private @property inout(size_t)* bitmaskPtr() inout
        {
            return cast(inout(size_t)*)bitmask.ptr;
        }

        uint[4] bitmask;
        Trie[] entries;
    }
    debug dchar _c;
    Priorities priorities;
    version (none)
        Trie[dchar] elems;
    else
        Table elems;
}

struct Hyphenator
{
    this(string s)
    {
        auto lines = s.splitter("\n");
        lines = lines.find!(a => a.startsWith(`\patterns{`))();
        lines.popFront();
        foreach (line; refRange(&lines).until!(a => a.startsWith("}"))())
        {
            insertPattern(line);
        }
        assert(lines.front.startsWith("}"));
        lines.popFront();
        assert(lines.front.startsWith(`\hyphenation{`));
        lines.popFront();
        foreach (line; refRange(&lines).until!(a => a.startsWith("}"))())
        {
            insertException(line);
        }
        assert(lines.front.startsWith("}"));
        lines.popFront();
        assert(lines.front.empty);
        lines.popFront();
        assert(lines.empty);
    }

    string hyphenate(string word) const
    {
        if (word.length <= 3) return word;

        static ubyte buf[];
        static Appender!string lower;
        lower.put(word.map!toLower());

        const(ubyte)[] prios;
        if (auto p = lower.data in exceptions)
            prios = *p;
        else
            prios = buildPrios(lower.data, buf);

        lower.clear();

        string res;
        assert(prios.length == word.length-1);
        res ~= word.front; word.popFront();
        foreach (c, prio; zip(word, prios))
        {
            if (prio & 1) res ~= HYPHEN;
            res ~= c;
        }
        return res;
    }

    ubyte[] buildPrios(string word, ref ubyte[] buf) const
    {
        auto search = chain(".", word, ".");
        if (buf.length < word.length + 3)
        {
            assumeSafeAppend(buf);
            buf.length = word.length + 3;
        }
        buf[] = 0;
        for (size_t pos; !search.empty; ++pos, search.popFront())
        {
            auto p = &root;
            foreach (c; search)
            {
                if ((p = c in p.elems) is null) break;
                size_t off;
                foreach (prio; cast()p.priorities)
                {
                    buf[pos + off] = max(buf[pos + off], prio);
                    ++off;
                }
            }
        }
        // trim priorities before and after leading '.'
        // trim priorities before and after trailing '.'
        auto slice = buf[2..2+word.length-1];
        // no hyphens after first or before last letter
        slice[0] = slice[$-1] = 0;
        return slice;
    }

    Leave findLeave(R)(R rng)
    {
        return root.getLeave(rng, false);
    }

    void insertPattern(R)(R rng)
    {
        auto p = &getTerminal(rng.letters);
        *p = rng.priorities;
    }

    private ref Priorities getTerminal(R)(R rng)
    {
        auto p = &root;
        foreach (c; rng)
            p = &p.elems.getLvalue(c);
        return p.priorities;
    }

    void insertException(string s)
    {
        auto prios = exceptionPriorities(s);
        s = s.filter!(a => a != '-')().to!string();
        exceptions[s] = prios;
    }

    static immutable(ubyte)[] exceptionPriorities(string s)
    {
        typeof(return) prios;
        for (s.popFront(); !s.empty; s.popFront())
        {
            if (s.front == '-')
                prios ~= 1, s.popFront();
            else
                prios ~= 0;
        }
        return prios;
    }

    unittest
    {
        assert(exceptionPriorities("as-so-ciate") == [0, 1, 0, 1, 0, 0, 0, 0]);
    }

    immutable(ubyte)[][string] exceptions;
    Trie root;
}

static immutable Hyphenator h;
shared static this()
{
    h = cast(immutable)Hyphenator(import("hyphen.tex"));
}

string hyphenateWords(string s)
{
    import std.regex;

    enum wordsRE = ctRegex!(`\w+`, "g");
    return s.replace!((c) => h.hyphenate(c.hit))(wordsRE);
}

string hyphenateHTML(string s)
{
    return s;
}

void main(string[] args)
{
    import std.file;

    foreach (file; args[1..$])
    {
        if (file.endsWith(".html"))
            write(file, file.readText.hyphenateHTML());
        else
            write(file, file.readText.hyphenateWords());
    }
}
