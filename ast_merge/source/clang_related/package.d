module clang_related;

import clang;
import std.algorithm;
import std.array;
import std.conv: to;
import std.range;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles
        | TranslationUnitFlags.KeepGoing; //Do not stop processing when fatal errors are encountered

    return parse(filename, args); //, flags);
}

struct Key
{
    Cursor.Kind kind;
    string[] paramTypes; // for functions
    bool isDefinition;
    string name;
}

/*private*/ Cursor[Key] addedDecls;

version(DebugOutput)  import std.stdio;

private bool[string][Cursor.Kind] ignoredDecls;

private void fillAA(Cursor.Kind kind, string[] names)
{
    import std.algorithm;

    bool[string] namesAA;
    names.each!(a => namesAA[a] = true);
    ignoredDecls[kind] = namesAA;
}

shared static this()
{
    with(Cursor.Kind)
    {
        fillAA(StaticAssert,    [""]);
        fillAA(StructDecl,      ["sigaction"]);
        fillAA(TypedefDecl,     ["##ANY##"]); //FIXME: remove
        fillAA(FunctionDecl, //FIXME: remove
            [
                "esp_log_buffer_hex",
                "esp_log_buffer_char",
                "is_valid_host",
                "spi_intr",
                "xTimerCreateTimerTask",
                "lookup_cmd_handler",
                "efuse_ll_set_pgm_cmd",
            ]
        );
        fillAA(VarDecl,
            [
                "TAG",
                "SPI_TAG",
                "spihost",
                "s_platform",
                "cmd_table",
            ]
        );
    }

    ignoredDecls.rehash;
}

void checkAndAdd(ref Cursor cur)
{
    import std.algorithm.comparison: equal;

    version(DebugOutput) cur.underlyingType.writeln;

    Key key = {
        name: cur.spelling,
        kind: cur.kind,
        paramTypes: cur.type.paramTypes.map!(a => a.spelling.idup).array,
        isDefinition: cur.isDefinition,
    };

    auto found = (key in addedDecls);

    if(found is null)
    {
        version(DebugOutput) writeln(cur, " not found");

        addedDecls[key] = cur;
    }
    else
        cmpCursors(key, *found, cur);
}

private void cmpCursors(Key key, Cursor old_orig, Cursor new_orig)
{
    Cursor _old;
    Cursor _new;

    {
        _old = old_orig;
        _new = new_orig;
    }

    const ignoreFuncArgsNames = (key.kind == Cursor.Kind.FunctionDecl && !key.isDefinition);

    const oldHash = _old.calcIndependentHash(ignoreFuncArgsNames);
    const newHash = _new.calcIndependentHash(ignoreFuncArgsNames);

    const succCmp = ignoreFuncArgsNames || (oldHash == newHash) || (_old.getPrettyPrinted == _new.getPrettyPrinted);

    if(!succCmp)
    {
        auto ignored = (key.kind in ignoredDecls);
        if(ignored !is null)
        {
            bool mathed =
                ((_old.spelling in *ignored) !is null) ||
                (("##ANY##" in *ignored) !is null);

            // we are on ignored cursor?
            if(mathed) return;
        }

        //~ deepCmpCursors(_old, _new);

        const osr = old_orig.getSourceRange;
        const nsr = new_orig.getSourceRange;

        throw new DifferentCursorsException(
            key, old_orig, new_orig, oldHash, newHash,
            "New cursor is not equal to previously saved:\n"
            ~"Old: "~osr.fileLinePrettyString~"\n"
            ~old_orig.getPrettyPrinted~"\n"
            ~"New: "~nsr.fileLinePrettyString~"\n"
            ~new_orig.getPrettyPrinted~"\n"
            ~"Old orig cursor: "~old_orig.toString~"\n"
            ~"New orig cursor: "~new_orig.toString~"\n"
            ~"Key param types: "~key.paramTypes.to!string~"\n"
            ~"Hash old: "~oldHash.to!string~"\n"
            ~"Hash new: "~newHash.to!string
        );
    }
}

class DifferentCursorsException : Exception
{
    Key key;
    Cursor c1;
    Cursor c2;
    IndependentHash h1;
    IndependentHash h2;

    this(Key key, Cursor c1, Cursor c2, IndependentHash h1, IndependentHash h2, string msg)
    {
        super(msg);
    }
}

version(DebugOutput)
private auto deepCmpCursors(in Cursor c1, in Cursor c2)
{
    Cursor[] r1;
    Cursor[] r2;

    c1.visitRecursive((c, p) { r1 ~= c; });
    c2.visitRecursive((c, p) { r2 ~= c; });

    r1.each!(a => stderr.writeln(a));
    stderr.writeln("=====");
    r2.each!(a => stderr.writeln(a));
}

alias IndependentHash = ubyte[16];

private IndependentHash calcIndependentHash(in Cursor c, bool ignoreArgNames)
{
    import clang.c.index;
    import std.digest.murmurhash;
    import std.string;
    import std.stdio;

    MurmurHash3!(128, 64) acc;

    import std.stdio;
    //~ writeln("calh hash of ", c);

    void calcHash(in Cursor cur, in Cursor parent)
    {
    with(Cursor.Kind)
    {
        //~ writeln(cur);
        if(cur.kind == Cursor.Kind.ParmDecl && ignoreArgNames)
        {
            auto t = Type(cur.type);
            auto c = Cursor(c.kind, "", t);

            acc.put(c.toString.representation);
        }
        else if(cur.kind == Cursor.Kind.FirstAttr && parent.kind == Cursor.Kind.FunctionDecl)
        {
            // ignore function __attribute__ cursors
        }
        else
            acc.put(cur.toString.representation);
    }
    }

    calcHash(c, c);
    c.visitRecursive(&calcHash);

    return acc.finish();
}

string getPrettyPrinted(in Cursor cur)
{
    import clang.c.index;

    return cur.cx.clang_getCursorPrettyPrinted(null).toString;
}

private auto getSourceRange(in Cursor c)
{
    import clang.c.index;

    //TODO: make libclang _sourceRangeCreate public

    return SourceRange(clang_getCursorExtent(c.cx));
}

private string fileLinePrettyString(in SourceRange r)
{
    return r.path~":"~r.start.line.to!string~":"~r.start.column.to!string;
}

void visitRecursive(const ref Cursor cursor, scope void delegate(Cursor cursor, Cursor parent) visitor) @safe
{
    ChildVisitResult internalVisitor(Cursor c, Cursor parent)
    {
        visitor(c, parent);
        return ChildVisitResult.Recurse;
    }

    cursor.visitChildren(&internalVisitor);
}
