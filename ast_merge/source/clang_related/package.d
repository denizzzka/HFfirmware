module clang_related;

//~ import clang.c.index: CXType_Pointer;
import clang;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles;

    return parse(filename, args); //, flags);
}

/*private*/ Cursor*[string] addedDecls;

void checkAndAdd(ref Cursor cur)
{
    auto found = (cur.spelling in addedDecls);

    import std.stdio;

    if(found is null)
    {
        writeln(cur, " not found");

        addedDecls[cur.spelling] = &cur;
    }
    else
    {
        writeln("Check ", cur, **found);

        const s1 = cur.getPrinted;
        const s2 = (**found).getPrinted;

        if(s1 != s2)
        {
            throw new Exception(cur.toString~" is not equal to previously saved "~(*found).toString~"\n"
                    ~s1~"\n"
                    ~s2~"\n"
                );
        }
    }
}

private string getPrinted(ref Cursor cur)
{
    import clang.c.index;

    //~ CXPrintingPolicyProperty props;

    return cur.cx.clang_getCursorPrettyPrinted(null).toString;
}
