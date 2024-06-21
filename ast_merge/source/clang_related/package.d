module clang_related;

import clang;
import std.conv: to;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles;

    return parse(filename, args); //, flags);
}

private struct Key
{
    bool isElaborated;
    string name;
}

/*private*/ Cursor*[Key] addedDecls;

void checkAndAdd(ref Cursor cur)
{
    assert(cur.isCanonical);

    import std.stdio;
    cur.underlyingType.writeln;

    Key key = { name: cur.spelling, isElaborated: cur.underlyingType.isInvalid };

    auto found = (key in addedDecls);

    import std.stdio;

    if(found is null)
    {
        writeln(cur, " not found");

        addedDecls[key] = &cur;
    }
    else
    {
        writeln("Check ", cur, **found);

        const _old = cur.getCursorForCmp;
        const _new = (**found).getCursorForCmp;

        if(_old != _new)
        {
            throw new Exception(
                "New cursor is not equal to previously saved:\n"
                ~"Old:\n"~_old.getPrinted~"\n"
                ~"New:\n"~_new.getPrinted
            );
        }
    }
}

private auto getCursorForCmp(ref Cursor c)
{
    auto d = c.definition;

    if(!d.isNull)
        return d;

    return c.canonical;
}

private string getPrinted(in Cursor cur)
{
    import clang.c.index;

    //~ CXPrintingPolicyProperty props;

    return cur.cx.clang_getCursorPrettyPrinted(null).toString;
}
