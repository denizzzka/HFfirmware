module clang_related;

import clang;
import std.conv: to;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles
        | TranslationUnitFlags.KeepGoing; //Do not stop processing when fatal errors are encountered

    return parse(filename, args); //, flags);
}

private struct Key
{
    Cursor.Kind kind;
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
        fillAA(VarDecl,         ["TAG"]);
        fillAA(StructDecl,      ["sigaction"]);
    }

    ignoredDecls.rehash;
}

void checkAndAdd(ref Cursor cur)
{
    import std.algorithm.comparison: equal;

    version(DebugOutput) cur.underlyingType.writeln;

    Key key = { name: cur.spelling, kind: cur.kind, isDefinition: cur.isDefinition };

    auto found = (key in addedDecls);

    import std.stdio;

    if(found is null)
    {
        writeln(cur, " not found");

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

    const ignoreArgsNames = (key.kind == Cursor.Kind.FunctionDecl && !_old.isDefinition)
        || key.kind == Cursor.Kind.TypedefDecl;

    const oldHash = _old.calcIndependentHash(ignoreArgsNames);
    const newHash = _new.calcIndependentHash(ignoreArgsNames);

    const succCmp = (oldHash == newHash);

    if(!succCmp)
    {
        auto ignored = (key.kind in ignoredDecls);
        if(ignored !is null)
        {
            auto mathed = (_old.spelling in (*ignored));

            // we are on ignored cursor?
            if(mathed !is null) return;
        }

        const osr = old_orig.getSourceRange;
        const nsr = new_orig.getSourceRange;

        throw new Exception(
            "New cursor is not equal to previously saved:\n"
            ~"Old: "~osr.fileLinePrettyString~"\n"
            ~old_orig.getPrettyPrinted~"\n"
            ~"New: "~nsr.fileLinePrettyString~"\n"
            ~new_orig.getPrettyPrinted~"\n"
            ~"Old orig cursor: "~old_orig.toString~"\n"
            ~"New orig cursor: "~new_orig.toString~"\n"
            ~"Hash old: "~oldHash.to!string~"\n"
            ~"Hash new: "~newHash.to!string
        );
    }
}

private bool funcDeclarationsEqual(in Cursor f1, in Cursor f2)
{
    assert(!f1.isDefinition);
    assert(!f2.isDefinition);

    return f1.spelling == f2.spelling;
}

private auto calcIndependentHash(in Cursor c, bool ignoreArgNames)
{
    import clang.c.index;
    import std.digest.murmurhash;
    import std.string;
    import std.stdio;

    MurmurHash3!(128, 64) acc;

    ChildVisitResult calcHash(in Cursor cur, in Cursor parent)
    {
        if(cur.kind == Cursor.Kind.ParmDecl && ignoreArgNames)
        {
            auto t = Type(cur.type);
            auto c = Cursor(c.kind, "", t);

            acc.put(c.toString.representation);
        }
        else
            acc.put(cur.toString.representation);

        return ChildVisitResult.Recurse;
    }

    calcHash(c, c);
    c.visitChildren(&calcHash);

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
